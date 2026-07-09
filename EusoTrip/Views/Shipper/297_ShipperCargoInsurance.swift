//
//  297_ShipperCargoInsurance.swift
//  EusoTrip — Shipper · Wallet · Cargo Insurance (EusoShield coverage roll-up + per-load insure).
//
//  Verbatim port of "297 Shipper Cargo Insurance.svg" (440×956, Dark/Light).
//  A WALLET-tab destination (BottomNav · WALLET active) — NOT a pushed detail,
//  so there is no back-chevron orb in the header (matches the SVG exactly).
//
//  Layout (section-by-section against the SVG):
//    • Header — eyebrow "✦ SHIPPER · CARGO INSURANCE" (gradient) on the left +
//      "{active} ACTIVE · {expiring} EXPIRING" (amber) on the right; title
//      "Cargo insurance" (34/700); subtitle "{shipper} · {coverage} all-risk ·
//      annual"; IridescentHairline.
//    • Hero card (gradient rim) — "CARGO COVERAGE · ALL-RISK · IN FORCE"; shield
//      glyph; big gradient "{perOccurrence}"; "per-occurrence limit · {aggregate}
//      aggregate"; hairline.
//    • Sub-KPI strip — two cells: "ANNUAL PREMIUM" {summary.annualPremium} and
//      "ACTIVE · EXPIRING" {active} · {expiring} soon.
//    • Policies card — "POLICIES · {n} · CARRIER COVERAGE ON FILE" header + one
//      row per live policy (icon, pretty name, provider · number, limit sub,
//      status badge {ACTIVE / EXPIRING Nd / EXPIRED}, "Manage →").
//    • Per-load quote card (teal wash) — the in-session computed quote (commodity,
//      lane, declared value, total premium) with a "+ Insure" pill. Empty until
//      the shipper runs a quote; never shows fabricated numbers.
//    • CTA row — "Request COI" (gradient) + "New quote" (secondary). Below: a
//      live "{n} certificate(s) on file" line.
//    • Per-load policies card — the EusoShield single-trip ledger
//      (insurance.getMyPerLoadPolicies), rendered on the loaded AND empty
//      branches so purchased per-load coverage is never invisible.
//    • Empty branch adds the FMCSA coverage-requirements ladder
//      (getCommodityInsuranceRequirements · general / reefer / hazmat cl. 3).
//    • Quote sheet (medium/large detents) — EusoShield-branded, shipper-scoped
//      "Insure one of your loads" picker (shippers.getMyLoads), live-debounced
//      indicative premium, gradient "Lock quote" CTA.
//    • BottomNav · WALLET active — supplied by the Shipper surface chrome (this
//      file is a tab destination; the host owns nav + WALLET-selected state,
//      identical to the sibling Shipper wallet screens).
//
//  Data (endpoints exactly as named in the wireframe <desc>, verified live):
//    insurance.getPolicies          (routers/insurance.ts:93)  query  → policy rows
//    insurance.getSummary           (routers/insurance.ts:219) query  → totals (tolerant: array/null → zeros)
//    insurance.getExpiringPolicies  (routers/insurance.ts:191) query  → which policies expire ≤30d
//    insurance.getCertificates      (routers/insurance.ts:442) query  → COIs on file
//    insurance.getPerLoadQuote      (routers/insurance.ts:1216) MUTATION → server-priced quote (live-debounced)
//    insurance.purchasePerLoad      (routers/insurance.ts:1259) MUTATION → buy per-load policy (wallet debit;
//                                   threads optional loadId — server input is z.coerce.number().optional())
//    insurance.requestCertificate   (routers/insurance.ts:468) MUTATION → request a COI
//    insurance.getMyPerLoadPolicies (routers/insurance.ts:1404) query → per-load EusoShield ledger
//                                   (server pre-parses money decimals to NUMBERS on this proc)
//    insurance.getCommodityInsuranceRequirements (routers/insurance.ts:2142) query → FMCSA
//                                   coverage-minimum ladder (rendered on the empty branch)
//    shippers.getMyLoads            (routers/shippers.ts:722) query → shipper-SCOPED load picker
//                                   for "Insure one of your loads" (loads.search is unscoped —
//                                   it would leak other shippers' loads into the picker, so the
//                                   picker reuses the 228 BOL-picker pattern / ShipperMyLoadsStore)
//
//  Verb note: getPerLoadQuote is registered as a tRPC `mutation` (POST) despite
//  being a pure read — it is called with `.mutation(...)` here on purpose (see
//  PREMORTEM #3). All money fields on policy rows are Drizzle `decimal` →
//  serialized as STRINGS; decoded as String? and parsed defensively
//  (PREMORTEM #6). No mock data in any path; unavailable values render an
//  em-dash, never a fabricated figure. The commodity rate labels and policy-type
//  display map are presentation/reference data, not business data.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Wire models (match the live insurance.* returns)

/// `insurance.getSummary` payload. Every field optional + a zeroed fallback so a
/// degraded server path (PREMORTEM #4: the `!db` branch can return `[]`) folds to
/// zeros instead of erroring the whole screen.
private struct InsuranceSummary: Decodable, Equatable {
    let total: Int?
    let active: Int?
    let expiringSoon: Int?
    let expired: Int?
    let totalCoverage: Double?
    let annualPremium: Double?

    static let zero = InsuranceSummary(total: 0, active: 0, expiringSoon: 0,
                                       expired: 0, totalCoverage: 0, annualPremium: 0)
}

/// One row from `insurance.getPolicies` / `getExpiringPolicies` (raw
/// `insurance_policies`). Money limits are decimals → STRINGS on the wire.
private struct InsurancePolicy: Decodable, Equatable, Identifiable {
    let id: Int
    let policyNumber: String
    let policyType: String
    let providerName: String?
    let perOccurrenceLimit: String?
    let aggregateLimit: String?
    let combinedSingleLimit: String?
    let cargoLimit: String?
    let deductible: String?
    let annualPremium: String?
    let status: String?
    let effectiveDate: String?
    let expirationDate: String?
    let hazmatClasses: [String]?
}

/// `insurance.getPerLoadQuote` result (server-priced).
private struct PerLoadQuote: Decodable, Equatable {
    let premium: Double
    let coverage: Double
    let deductible: Double
    let hazmatSurcharge: Double
    let reeferSurcharge: Double
    let highValueSurcharge: Double
    let totalPremium: Double
    let policyType: String
    let validUntil: String?
}

/// `insurance.purchasePerLoad` result.
private struct PurchasePerLoadResult: Decodable, Equatable {
    let success: Bool
    let policyNumber: String?
    let platformCommission: Double?
}

/// One row from `insurance.getCertificates` (raw `certificates_of_insurance`).
private struct InsuranceCertificate: Decodable, Equatable, Identifiable {
    let id: Int
    let certificateNumber: String?
    let holderName: String
    let status: String?
    let issuedDate: String?
}

/// `insurance.requestCertificate` result.
private struct RequestCertificateResult: Decodable, Equatable {
    let success: Bool
    let certificateId: Int?
    let certificateNumber: String?
}

/// One row from `insurance.getMyPerLoadPolicies` (insurance.ts:1404) — the
/// per-load EusoShield ledger. Unlike the annual-policy rows, this proc
/// pre-parses its money decimals server-side, so these are NUMBERS on the wire.
private struct PerLoadPolicy: Decodable, Equatable, Identifiable {
    let id: String
    let policyNumber: String
    let coverageAmount: Double?
    let premium: Double?
    let commodityType: String?
    let policyType: String?
    let status: String?
    let origin: String?
    let destination: String?
    let activatedAt: String?
    let expiresAt: String?
}

/// One rung from `insurance.getCommodityInsuranceRequirements`
/// (insurance.ts:2142) — FMCSA coverage minimums per commodity category.
/// Server values only; the ladder never invents a dollar figure.
private struct CommodityRequirement: Decodable, Equatable {
    let commodityType: String
    let category: String
    let minLiability: Double
    let minCargo: Double
    let specialEndorsements: [String]
    let notes: String
}

/// Everything the screen renders in one settled state.
private struct CargoInsuranceModel: Equatable {
    let summary: InsuranceSummary
    let policies: [InsurancePolicy]
    let expiringIds: Set<Int>
    let certificates: [InsuranceCertificate]
}

// MARK: - Store

@MainActor
private final class CargoInsuranceStore: BaseDynamicStore<CargoInsuranceModel> {

    private struct PoliciesIn: Encodable { let filter: String?; let limit: Int?; let policyType: String? }
    private struct CertsIn: Encodable { let limit: Int? }
    private struct PerLoadIn: Encodable { let status: String?; let limit: Int }
    private struct ReqIn: Encodable { let commodityType: String; let hazmatClass: String? }

    /// Per-load EusoShield ledger (insurance.getMyPerLoadPolicies). Published
    /// OUTSIDE the RemoteState model because `.empty` carries no payload —
    /// the enriched empty branch still needs these rows. Tolerant fetch;
    /// `[]` is the honest degraded value, never a fabricated row.
    @Published var perLoadPolicies: [PerLoadPolicy] = []

    /// FMCSA coverage-requirements ladder (getCommodityInsuranceRequirements).
    /// Fetched only when there are no annual policies on file (the ladder
    /// renders on the empty branch), all values verbatim from the server.
    @Published var requirementLadder: [CommodityRequirement] = []

    /// Treat "no policies AND no coverage on file" as a real empty set so the
    /// branded empty card shows; otherwise render (a zeroed hero is still valid
    /// — a shipper with $0 coverage should see $0, not a spinner).
    override func foldState(_ value: CargoInsuranceModel) -> RemoteState<CargoInsuranceModel> {
        if value.policies.isEmpty && (value.summary.total ?? 0) == 0 { return .empty }
        return .loaded(value)
    }

    override func fetch() async throws -> CargoInsuranceModel {
        // Primary, load-blocking read — getPolicies returns a clean [] on the
        // degraded path, so it's the safe gate for the whole screen.
        let policies: [InsurancePolicy] = try await EusoTripAPI.shared.query(
            "insurance.getPolicies",
            input: PoliciesIn(filter: nil, limit: nil, policyType: nil)
        )

        // Tolerant summary: an array/null from the `!db` branch (PREMORTEM #4)
        // degrades to zeros rather than throwing the whole screen to .error.
        let summary: InsuranceSummary = (try? await EusoTripAPI.shared.queryNoInput(
            "insurance.getSummary"
        )) ?? .zero

        // Non-blocking enrichment: which policies the server flags as expiring.
        let expiring: [InsurancePolicy] = (try? await EusoTripAPI.shared.queryNoInput(
            "insurance.getExpiringPolicies"
        )) ?? []

        // Non-blocking: certificates on file (drives the COI count line).
        let certs: [InsuranceCertificate] = (try? await EusoTripAPI.shared.query(
            "insurance.getCertificates",
            input: CertsIn(limit: 25)
        )) ?? []

        // Non-blocking: per-load EusoShield ledger — history for the
        // "Per-load policies" card on BOTH the loaded and empty branches.
        perLoadPolicies = (try? await EusoTripAPI.shared.query(
            "insurance.getMyPerLoadPolicies",
            input: PerLoadIn(status: nil, limit: 10)
        )) ?? []

        // Non-blocking, empty-branch only: FMCSA coverage-minimum ladder.
        // Three probes (general / reefer / hazmat class 3) — each rung is the
        // server's verbatim requirement row; a failed probe simply drops out.
        if policies.isEmpty {
            var ladder: [CommodityRequirement] = []
            for probe: (type: String, hazmat: String?) in
                [("general", nil), ("reefer", nil), ("hazmat", "3")] {
                if let rung: CommodityRequirement = try? await EusoTripAPI.shared.query(
                    "insurance.getCommodityInsuranceRequirements",
                    input: ReqIn(commodityType: probe.type, hazmatClass: probe.hazmat)
                ) { ladder.append(rung) }
            }
            requirementLadder = ladder
        } else {
            requirementLadder = []
        }

        return CargoInsuranceModel(
            summary: summary,
            policies: policies,
            expiringIds: Set(expiring.map(\.id)),
            certificates: certs
        )
    }
}

// MARK: - Screen root

struct ShipperCargoInsurance: View {
    @Environment(\.palette) var palette
    @StateObject private var store = CargoInsuranceStore()

    /// Shipper identity for the subtitle. Server-first where a name is available;
    /// these endpoints don't carry the company name, so we fall back to the
    /// caller-supplied name (SVG canon: "Eusorone Technologies").
    private let shipperName: String
    init(shipperName: String = "Eusorone Technologies") { self.shipperName = shipperName }

    // Per-load quote flow (in-session). Held on the parent so the verbatim quote
    // card stays in place and "+ Insure" can act on it.
    @State private var quoteSheet = false
    @State private var coiSheet = false
    @State private var activeQuote: PerLoadQuote? = nil
    @State private var activeQuoteInputs: PerLoadQuoteInputs? = nil
    @State private var purchasing = false
    @State private var banner: ActionBanner? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                switch store.state {
                case .loading:
                    skeleton
                case .empty:
                    emptyCard
                    if !store.perLoadPolicies.isEmpty {
                        perLoadHistoryCard(store.perLoadPolicies)
                    }
                    if !store.requirementLadder.isEmpty {
                        requirementsLadder(store.requirementLadder)
                    }
                case .error(let e):
                    errorBanner(e)
                case .loaded(let model):
                    heroCard(model)
                    kpiStrip(model.summary)
                    policiesCard(model)
                    perLoadQuoteCard
                    ctaRow
                    certificateLine(model.certificates)
                    if !store.perLoadPolicies.isEmpty {
                        perLoadHistoryCard(store.perLoadPolicies)
                    }
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .overlay(alignment: .top) { bannerView }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $quoteSheet) {
            // Detents kill the dead bottom half: the sheet opens at .medium
            // (form-height) and grows to .large only when the shipper pulls it.
            PerLoadQuoteSheet { quote, inputs in
                activeQuote = quote
                activeQuoteInputs = inputs
            }
            .environment(\.palette, palette)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $coiSheet) {
            RequestCOISheet { result in
                banner = .success("COI requested · \(result.certificateNumber ?? "pending")")
                Task { await store.refresh() }
            }
            .environment(\.palette, palette)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Header (no back-orb — WALLET tab root)

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("✦ SHIPPER · CARGO INSURANCE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(headerPill)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(Brand.warning)
            }
            Text("Cargo insurance")
                .font(.system(size: 32, weight: .bold)).tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Text(subtitle)
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            IridescentHairline()
        }
    }

    private var headerPill: String {
        let s = store.state.value?.summary
        let active = s?.active ?? 0
        let exp = s?.expiringSoon ?? 0
        return "\(active) ACTIVE · \(exp) EXPIRING"
    }

    private var subtitle: String {
        let cov = headlineCoverageText
        if cov == "-" { return "\(shipperName) · cargo all-risk · annual" }
        return "\(shipperName) · \(cov) all-risk · annual"
    }

    // MARK: Hero card (gradient rim)

    private func heroCard(_ m: CargoInsuranceModel) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                Text("CARGO COVERAGE · ALL-RISK · IN FORCE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                shieldGlyph
            }
            Text(headlineCoverageText)
                .font(.system(size: 34, weight: .bold)).monospacedDigit()
                .foregroundStyle(LinearGradient.diagonal)
            Text("per-occurrence limit · \(aggregateText) aggregate")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            Rectangle().fill(palette.textTertiary.opacity(0.08)).frame(height: 1)
                .padding(.top, 2)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.85), lineWidth: 1.5)
        )
    }

    private var shieldGlyph: some View {
        Image(systemName: "checkmark.shield.fill")
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(LinearGradient.diagonal)
            .opacity(0.9)
    }

    // MARK: KPI strip

    private func kpiStrip(_ s: InsuranceSummary) -> some View {
        HStack(spacing: Space.s2) {
            kpiCell(label: "ANNUAL PREMIUM",
                    value: s.annualPremium.map(grouped) ?? "-",
                    accent: nil)
            kpiCell(label: "ACTIVE · EXPIRING",
                    value: "\(s.active ?? 0)",
                    accent: (s.expiringSoon ?? 0) > 0 ? "· \(s.expiringSoon ?? 0) soon" : nil)
        }
    }

    private func kpiCell(label: String, value: String, accent: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(EType.micro).tracking(0.5).foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                if let accent {
                    Text(accent).font(EType.caption).foregroundStyle(Brand.warning)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1))
    }

    // MARK: Policies card

    private func policiesCard(_ m: CargoInsuranceModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("POLICIES · \(m.policies.count) · CARRIER COVERAGE ON FILE")
                .font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
                .padding(.bottom, Space.s3)

            if m.policies.isEmpty {
                Text("No policies on file yet")
                    .font(EType.caption.monospaced()).foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, Space.s2)
            } else {
                ForEach(Array(m.policies.enumerated()), id: \.element.id) { idx, p in
                    policyRow(p, expiring: m.expiringIds.contains(p.id))
                    if idx < m.policies.count - 1 {
                        Rectangle().fill(palette.textTertiary.opacity(0.08))
                            .frame(height: 1).padding(.vertical, Space.s3)
                    }
                }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func policyRow(_ p: InsurancePolicy, expiring: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(LinearGradient.diagonal.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 16)).foregroundStyle(LinearGradient.diagonal))
            VStack(alignment: .leading, spacing: 3) {
                Text(prettyType(p.policyType)).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("\(p.providerName ?? "-") · \(p.policyNumber)")
                    .font(EType.caption.monospaced()).foregroundStyle(palette.textSecondary).lineLimit(1)
                Text(policySubline(p)).font(EType.micro).foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                statusBadge(p, expiring: expiring)
                Text("Manage →").font(EType.caption.weight(.semibold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ p: InsurancePolicy, expiring: Bool) -> some View {
        let st = (p.status ?? "").lowercased()
        if st == "expired" {
            badgeText("EXPIRED", Brand.danger)
        } else if (expiring || st == "lapsed"), let d = daysUntil(p.expirationDate), d >= 0 {
            badgeText("EXPIRING \(d)D", Brand.warning)
        } else if st == "active" {
            badgeText("ACTIVE", Brand.success)
        } else {
            badgeText((p.status ?? "-").uppercased(), palette.textTertiary)
        }
    }

    private func badgeText(_ s: String, _ color: Color) -> some View {
        Text(s).font(.system(size: 9, weight: .bold)).tracking(0.5).foregroundStyle(color)
    }

    // MARK: Per-load quote card (teal wash)

    private var perLoadQuoteCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let q = activeQuote, let inp = activeQuoteInputs {
                HStack(alignment: .top) {
                    Text("PER-LOAD QUOTE · \(commodityLabel(inp.commodityType).uppercased())")
                        .font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(grouped(q.totalPremium))
                        .font(.system(size: 22, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("\(inp.origin) → \(inp.destination)")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(quoteDeclaredLine(q, inp))
                    .font(EType.caption.monospaced()).foregroundStyle(palette.textSecondary).lineLimit(1)
                perilCoverageLine
                HStack {
                    Text("deductible \(grouped(q.deductible)) · coverage \(grouped(q.coverage))")
                        .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Button { Task { await purchase(q, inp) } } label: {
                        HStack(spacing: 5) {
                            if purchasing { ProgressView().scaleEffect(0.7) }
                            Text(purchasing ? "Insuring…" : "+ Insure")
                                .font(EType.caption.weight(.bold)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, Space.s3).padding(.vertical, 7)
                        .background(Capsule().fill(LinearGradient.diagonal))
                    }
                    .buttonStyle(.plain).disabled(purchasing)
                }
            } else {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PER-LOAD QUOTE")
                            .font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
                        Text("Quote a load to insure it for a single trip")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "shippingbox").font(.system(size: 22))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(Brand.success.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.success.opacity(0.18), lineWidth: 1))
    }

    /// "$44,000 declared · LOAD-1077 · All-Risk Cargo" — the linked load
    /// number appears only when the quote was prefilled from a real load.
    private func quoteDeclaredLine(_ q: PerLoadQuote, _ inp: PerLoadQuoteInputs) -> String {
        var bits = ["\(grouped(Double(inp.cargoValue))) declared"]
        if let n = inp.loadNumber, !n.isEmpty { bits.append(n) }
        bits.append(q.policyType)
        return bits.joined(separator: " · ")
    }

    // MARK: Peril-coverage line (bespoke · WeatherIcons, zero SF Symbols)

    /// An honest, enterprise-gated PERIL-COVERAGE awareness line on the active
    /// quote — the wallet roll-up has no loadId in scope, so it cannot tag a
    /// real `insurance.getLoadPerilExposure` named-storm corridor / freeze
    /// here. Rather than fabricate one, it states plainly that per-load peril
    /// exposure (named-storm corridor / freeze) lights once the load is insured
    /// and the enterprise feed is licensed — the load-context tag lives on the
    /// insured load's detail (325). Bespoke glyphs only (WeatherIcons storm +
    /// alert), never an SF Symbol, never a fabricated storm.
    private var perilCoverageLine: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Brand.info.opacity(0.12))
                    .frame(width: 26, height: 26)
                WeatherIcons.symbolView(for: 8000, size: 17)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    WeatherIcons.utility(.alert, size: 10, tint: Brand.info)
                    Text("PERIL EXPOSURE")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(Brand.info)
                }
                Text("Named-storm corridor & freeze peril tags attach to the insured load with the enterprise feed.")
                    .font(EType.micro).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    // MARK: CTA row + certificate line

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { coiSheet = true } label: {
                Text("Request COI").font(EType.bodyStrong).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, Space.s3)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.diagonal))
            }.buttonStyle(.plain)

            Button { quoteSheet = true } label: {
                Text("New quote").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .frame(width: 124).padding(.vertical, Space.s3)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }

    private func certificateLine(_ certs: [InsuranceCertificate]) -> some View {
        let n = certs.count
        let pending = certs.filter { ($0.status ?? "").lowercased() == "pending" }.count
        return Text(n == 0
                    ? "No certificates of insurance on file yet"
                    : "\(n) certificate\(n == 1 ? "" : "s") on file\(pending > 0 ? " · \(pending) pending" : "")")
            .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Per-load policy history (insurance.getMyPerLoadPolicies)

    /// The per-load EusoShield ledger — every single-trip policy this shipper
    /// has bought, live from `insurance.getMyPerLoadPolicies`. Renders on the
    /// loaded branch (below the COI line) AND the empty branch, so a shipper
    /// with zero annual policies still sees the per-load coverage they own.
    private func perLoadHistoryCard(_ rows: [PerLoadPolicy]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PER-LOAD POLICIES · \(rows.count) · EUSOSHIELD")
                .font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
                .padding(.bottom, Space.s3)
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, p in
                perLoadPolicyRow(p)
                if idx < rows.count - 1 { rowDivider }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func perLoadPolicyRow(_ p: PerLoadPolicy) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(LinearGradient.diagonal.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "shippingbox.fill")
                    .font(.system(size: 15)).foregroundStyle(LinearGradient.diagonal))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(p.origin ?? "-") → \(p.destination ?? "-")")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(p.policyNumber)
                    .font(EType.caption.monospaced()).foregroundStyle(palette.textSecondary).lineLimit(1)
                Text(perLoadSubline(p)).font(EType.micro).foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                perLoadStatusBadge(p)
                if let prem = p.premium, prem > 0 {
                    Text(grouped(prem))
                        .font(EType.caption.monospaced()).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private func perLoadSubline(_ p: PerLoadPolicy) -> String {
        var bits: [String] = []
        if let cov = p.coverageAmount, cov > 0 { bits.append("\(compact(cov)) coverage") }
        if let c = p.commodityType, !c.isEmpty { bits.append(commodityLabel(c)) }
        if let exp = p.expiresAt, let d = daysUntil(exp), d >= 0 { bits.append("expires \(d)d") }
        return bits.isEmpty ? (p.policyType ?? "-") : bits.joined(separator: " · ")
    }

    @ViewBuilder
    private func perLoadStatusBadge(_ p: PerLoadPolicy) -> some View {
        switch (p.status ?? "").lowercased() {
        case "active":  badgeText("ACTIVE", Brand.success)
        case "expired": badgeText("EXPIRED", Brand.danger)
        case "claimed": badgeText("CLAIMED", Brand.warning)
        default:        badgeText((p.status ?? "-").uppercased(), palette.textTertiary)
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(palette.textTertiary.opacity(0.08))
            .frame(height: 1).padding(.vertical, Space.s3)
    }

    // MARK: Coverage-requirements ladder (getCommodityInsuranceRequirements)

    /// FMCSA coverage-minimum ladder — empty-branch education so a shipper
    /// with no coverage on file sees what the law requires before quoting.
    /// Every dollar figure / endorsement / note is the server's verbatim row.
    private func requirementsLadder(_ rungs: [CommodityRequirement]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("COVERAGE REQUIREMENTS · FMCSA MINIMUMS")
                .font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
                .padding(.bottom, Space.s3)
            ForEach(Array(rungs.enumerated()), id: \.element.category) { idx, r in
                ladderRung(r)
                if idx < rungs.count - 1 { rowDivider }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func ladderRung(_ r: CommodityRequirement) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(ladderLabel(r.category))
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(compact(r.minLiability)) liability · \(compact(r.minCargo)) cargo")
                    .font(EType.caption.monospaced())
                    .foregroundStyle(LinearGradient.diagonal)
            }
            if !r.specialEndorsements.isEmpty {
                Text(r.specialEndorsements.joined(separator: " · "))
                    .font(EType.micro.monospaced()).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Text(r.notes).font(EType.micro).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
    }

    private func ladderLabel(_ category: String) -> String {
        switch category {
        case "general":       return "General freight"
        case "reefer":        return "Reefer · temperature-controlled"
        case "hazmat_class1": return "Hazmat · Class 1 explosives"
        case "hazmat_class2": return "Hazmat · Class 2 gas"
        case "hazmat_class3": return "Hazmat · Class 3 flammable"
        case "hazmat_class7": return "Hazmat · Class 7 radioactive"
        case "hazmat_other":  return "Hazmat · other classes"
        case "oil_gas":       return "Oil & gas"
        default: return category.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: Purchase (real mutation — do/catch, never try?-??)

    private func purchase(_ q: PerLoadQuote, _ inp: PerLoadQuoteInputs) async {
        purchasing = true
        defer { purchasing = false }
        struct PurchaseIn: Encodable {
            let cargoValue: Double; let coverageAmount: Double; let deductible: Double
            let premium: Double; let basePremium: Double
            let hazmatSurcharge: Double; let reeferSurcharge: Double; let highValueSurcharge: Double
            let commodityType: String; let policyType: String
            let origin: String; let destination: String
            /// Links the policy to a real load when the quote was prefilled
            /// from the "Insure one of your loads" picker. Server input is
            /// `z.coerce.number().optional()` (insurance.ts purchasePerLoad)
            /// — nil encodes as absent, which the server folds to NULL.
            let loadId: Int?
        }
        do {
            let result: PurchasePerLoadResult = try await EusoTripAPI.shared.mutation(
                "insurance.purchasePerLoad",
                input: PurchaseIn(
                    cargoValue: Double(inp.cargoValue),
                    coverageAmount: q.coverage,
                    deductible: q.deductible,
                    premium: q.totalPremium,
                    basePremium: q.premium,
                    hazmatSurcharge: q.hazmatSurcharge,
                    reeferSurcharge: q.reeferSurcharge,
                    highValueSurcharge: q.highValueSurcharge,
                    commodityType: inp.commodityType,
                    policyType: q.policyType,
                    origin: inp.origin,
                    destination: inp.destination,
                    loadId: inp.loadId
                )
            )
            if result.success {
                banner = .success("Insured · \(result.policyNumber ?? "policy active") · \(grouped(q.totalPremium)) debited")
                activeQuote = nil
                activeQuoteInputs = nil
                await store.refresh()
            } else {
                banner = .error("Purchase did not complete. No charge was made.")
            }
        } catch {
            banner = .error(error.localizedDescription)
        }
    }

    // MARK: Derived display values (server-first, em-dash on absence)

    /// Headline per-occurrence coverage: the largest cargo/all-risk policy's
    /// per-occurrence limit; falls back to the summary's total coverage.
    private var headlineCoverageText: String {
        let policies = store.state.value?.policies ?? []
        let cargo = policies
            .filter { $0.policyType.contains("cargo") && ($0.status ?? "") == "active" }
            .compactMap { money($0.perOccurrenceLimit ?? $0.cargoLimit) }
            .max()
        if let cargo, cargo > 0 { return compact(cargo) }
        if let tc = store.state.value?.summary.totalCoverage, tc > 0 { return compact(tc) }
        return "-"
    }

    private var aggregateText: String {
        let policies = store.state.value?.policies ?? []
        let agg = policies
            .filter { $0.policyType.contains("cargo") }
            .compactMap { money($0.aggregateLimit) }
            .max()
        return agg.map(compact) ?? "-"
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard).frame(height: 116)
            HStack(spacing: Space.s2) {
                RoundedRectangle(cornerRadius: Radius.md).fill(palette.bgCard).frame(height: 64)
                RoundedRectangle(cornerRadius: Radius.md).fill(palette.bgCard).frame(height: 64)
            }
            RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard).frame(height: 166)
        }
        .redacted(reason: .placeholder)
    }

    private var emptyCard: some View {
        VStack(spacing: Space.s2) {
            Text("No cargo coverage yet").font(EType.title).foregroundStyle(palette.textPrimary)
            Text("Policies appear here once your carrier coverage is on file. You can still quote and insure a single load below.")
                .font(EType.caption).foregroundStyle(palette.textTertiary).multilineTextAlignment(.center)
            Button { quoteSheet = true } label: {
                Text("Quote a load").font(EType.bodyStrong).foregroundStyle(.white)
                    .padding(.horizontal, Space.s4).padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }.buttonStyle(.plain).padding(.top, Space.s2)
        }
        .frame(maxWidth: .infinity).padding(Space.s4).eusoCard(radius: Radius.lg)
        // NOTE: the "Quote a load" button only sets `quoteSheet = true`; the
        // body-level `.sheet(isPresented: $quoteSheet)` presents it. A second
        // sheet bound to the same flag here would double-present (scrutinize pass).
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Text("Couldn't load insurance").font(EType.title).foregroundStyle(palette.textPrimary)
            Text(err.eusoUserCopy).font(EType.caption)
                .foregroundStyle(palette.textTertiary).multilineTextAlignment(.center)
            Button { Task { await store.refresh() } } label: {
                Text("Retry").font(EType.bodyStrong).foregroundStyle(.white)
                    .padding(.horizontal, Space.s4).padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(Space.s4).eusoCard(radius: Radius.lg)
    }

    @ViewBuilder
    private var bannerView: some View {
        if let b = banner {
            HStack(spacing: 8) {
                Image(systemName: b.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                Text(b.message).font(EType.caption.weight(.semibold)).lineLimit(2)
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
            .background(RoundedRectangle(cornerRadius: Radius.md)
                .fill(b.isError ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(Brand.success)))
            .padding(.horizontal, Space.s4).padding(.top, Space.s2)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation { banner = nil }
            }
        }
    }

    // MARK: Formatting + reference data

    /// decimal-string → Double (PREMORTEM #6: tolerate string OR number-as-string).
    private func money(_ s: String?) -> Double? {
        guard let s, !s.isEmpty else { return nil }
        return Double(s)
    }

    /// $5.0M / $250K / $48,200 — compact for big coverage figures.
    private func compact(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "$%.0fK", v / 1_000) }
        return grouped(v)
    }

    /// $48,200 — grouped, no decimals for whole dollars.
    private func grouped(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = v.rounded() == v ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    private func prettyType(_ t: String) -> String {
        switch t {
        case "cargo": return "Cargo · All-Risk"
        case "motor_truck_cargo": return "Motor Truck Cargo"
        case "hazmat_endorsement": return "Hazmat Endorsement"
        case "auto_liability": return "Auto Liability"
        case "general_liability": return "General Liability"
        case "umbrella_excess": return "Umbrella / Excess"
        case "pollution_liability": return "Pollution Liability"
        case "physical_damage": return "Physical Damage"
        case "reefer_breakdown": return "Reefer Breakdown"
        case "trailer_interchange": return "Trailer Interchange"
        default: return t.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func policySubline(_ p: InsurancePolicy) -> String {
        if let classes = p.hazmatClasses, !classes.isEmpty { return classes.joined(separator: " · ") }
        if let lim = money(p.perOccurrenceLimit ?? p.cargoLimit) { return "\(compact(lim)) limit" }
        if let csl = money(p.combinedSingleLimit) { return "\(compact(csl)) CSL" }
        return prettyType(p.policyType)
    }

    private func commodityLabel(_ k: String) -> String { PerLoadCommodity.label(k) }

    /// ISO-8601 / yyyy-MM-dd → whole days until that date (nil if unparseable).
    private func daysUntil(_ iso: String?) -> Int? {
        guard let iso, !iso.isEmpty, let d = Self.parseDate(iso) else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: d).day
    }

    static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
}

// MARK: - Action banner

private struct ActionBanner: Equatable {
    let message: String
    let isError: Bool
    static func success(_ m: String) -> ActionBanner { .init(message: m, isError: false) }
    static func error(_ m: String) -> ActionBanner { .init(message: m, isError: true) }
}

// MARK: - Per-load quote inputs + commodity table

private struct PerLoadQuoteInputs: Equatable {
    let commodityType: String
    let cargoValue: Int
    let coverageAmount: Int
    let origin: String
    let destination: String
    /// Set only when the quote was prefilled from the shipper's own load via
    /// the "Insure one of your loads" picker — threaded into
    /// `insurance.purchasePerLoad` so the policy row links to the real load.
    let loadId: Int?
    let loadNumber: String?
}

/// Server rate-table keys (insurance.ts:896). Labels are presentation-only.
private enum PerLoadCommodity {
    static let all: [(key: String, label: String)] = [
        ("general", "General Freight"), ("electronics", "Electronics"),
        ("food_dry", "Food · Dry"), ("food_reefer", "Food · Reefer"),
        ("pharma", "Pharma"), ("machinery", "Machinery"), ("auto", "Automotive"),
        ("crude_oil", "Crude Oil"),
        ("hazmat_flammable", "Hazmat · Flammable"), ("hazmat_corrosive", "Hazmat · Corrosive"),
        ("hazmat_gas", "Hazmat · Gas"), ("hazmat_explosive", "Hazmat · Explosive"),
        ("hazmat_radioactive", "Hazmat · Radioactive"),
    ]
    static func label(_ key: String) -> String {
        all.first { $0.key == key }?.label ?? key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Per-load quote sheet (insurance.getPerLoadQuote — a tRPC mutation)

private struct PerLoadQuoteSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) var dismiss
    let onQuoted: (PerLoadQuote, PerLoadQuoteInputs) -> Void

    /// Shipper-SCOPED loads for the "Insure one of your loads" picker —
    /// `shippers.getMyLoads` via the existing ShipperMyLoadsStore (the same
    /// store the 228 BOL picker uses). `loads.search` is deliberately NOT
    /// used here: that proc is unscoped and would leak other shippers' loads.
    @StateObject private var loadsStore = ShipperMyLoadsStore()

    @State private var commodity = "general"
    @State private var origin = ""
    @State private var destination = ""
    @State private var cargoValue = ""
    @State private var pickedLoadId: Int? = nil
    @State private var pickedLoadNumber: String? = nil
    @State private var valuePrefilledFromRate = false
    @State private var showLoadPicker = false
    @State private var loading = false
    @State private var quote: PerLoadQuote? = nil
    @State private var errorText: String? = nil
    /// Monotonic round counter — `.task(id:)` cancels the stale debounce task
    /// but does not await it, so each round guards its own writes.
    @State private var quoteRound = 0

    private var cargoValueInt: Int { Int(cargoValue.filter(\.isNumber)) ?? 0 }
    private var canQuote: Bool { cargoValueInt > 0 && !origin.isEmpty && !destination.isEmpty }
    /// Debounce identity — any input change re-arms the 600 ms live-pricing task.
    private var quoteKey: String { "\(commodity)|\(cargoValueInt)|\(origin)|\(destination)" }

    /// Statuses past the point of insuring a trip — filtered OUT of the picker.
    private static let closedStatuses: Set<String> = [
        "delivered", "invoiced", "disputed", "paid", "complete",
        "cancelled", "expired", "declined", "lapsed",
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                sheetHeader
                loadPickerSection
                inputFields
                if let q = quote { quoteResultCard(q) }
                if let e = errorText {
                    Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                }
                lockCTA
            }
            .padding(Space.s4)
        }
        .background(palette.bgPrimary)
        .task { await loadsStore.refresh() }
        .task(id: quoteKey) { await debouncedQuote() }
    }

    // MARK: Header — EusoShield house style (gradient eyebrow + hairline + shield)

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                Text("✦ EUSOSHIELD · PER-LOAD QUOTE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Button { dismiss() } label: {
                    Text("Close").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
                }.buttonStyle(.plain)
            }
            HStack(alignment: .center, spacing: Space.s2) {
                Text("Insure a single load")
                    .font(EType.h2).foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(LinearGradient.diagonal)
                    .opacity(0.9)
            }
            Text("All-risk coverage for one trip · priced live as you type")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            IridescentHairline()
        }
    }

    // MARK: "Insure one of your loads" picker (shippers.getMyLoads)

    @ViewBuilder
    private var loadPickerSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("INSURE ONE OF YOUR LOADS")
                .font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            if let n = pickedLoadNumber {
                // Selected-load chip — gradient rim marks the live link.
                HStack(spacing: Space.s2) {
                    Image(systemName: "shippingbox.fill").font(.system(size: 14))
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                        Text("\(origin) → \(destination)")
                            .font(EType.caption.monospaced())
                            .foregroundStyle(palette.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Button { clearPickedLoad() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16))
                            .foregroundStyle(palette.textTertiary)
                    }.buttonStyle(.plain)
                }
                .padding(Space.s3)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.85), lineWidth: 1.5))
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { showLoadPicker.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "shippingbox").font(.system(size: 13))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("Prefill from one of your loads")
                            .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Image(systemName: showLoadPicker ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(Space.s3)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1))
                }.buttonStyle(.plain)
                if showLoadPicker { loadRows }
            }
        }
    }

    @ViewBuilder
    private var loadRows: some View {
        switch loadsStore.state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Loading your loads…")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
            }
            .padding(.vertical, Space.s2)
        case .empty:
            Text("No open loads to insure yet — enter the trip manually below.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
        case .error:
            Text("Couldn't reach your loads — enter the trip manually below.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
        case .loaded(let rows):
            let open = rows.filter { !Self.closedStatuses.contains($0.status.lowercased()) }
            if open.isEmpty {
                Text("No open loads to insure — enter the trip manually below.")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
            } else {
                VStack(spacing: 8) {
                    ForEach(open.prefix(8)) { l in loadRow(l) }
                }
            }
        }
    }

    private func loadRow(_ l: ShipperAPI.MyLoad) -> some View {
        Button { pick(l) } label: {
            HStack(spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.loadNumber)
                        .font(EType.caption.weight(.bold)).foregroundStyle(palette.textPrimary)
                    Text("\(l.origin) → \(l.destination)")
                        .font(EType.micro.monospaced())
                        .foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(l.status.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 8, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Brand.info)
                    if let r = l.rate, r > 0 {
                        Text(currency(r))
                            .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .padding(Space.s3)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func pick(_ l: ShipperAPI.MyLoad) {
        pickedLoadId = Int(l.id)
        pickedLoadNumber = l.loadNumber
        origin = l.origin
        destination = l.destination
        // Declared-value seed: the load's line-haul rate is the only real
        // dollar figure the row carries. Provenance is shown in the field
        // hint and the field stays editable — the shipper adjusts it to the
        // cargo's true declared value. Blank when the load has no rate;
        // never an invented figure.
        if let r = l.rate, r > 0 {
            cargoValue = String(Int(r))
            valuePrefilledFromRate = true
        } else {
            valuePrefilledFromRate = false
        }
        commodity = Self.commodityKey(for: l)
        withAnimation(.easeOut(duration: 0.12)) { showLoadPicker = false }
    }

    private func clearPickedLoad() {
        pickedLoadId = nil
        pickedLoadNumber = nil
        valuePrefilledFromRate = false
    }

    /// Real server fields (hazmat flag + class, equipment, product) → the
    /// server rate-table key (insurance.ts getPerLoadQuote RATES). A UI
    /// convenience only — the shipper can change the picker afterwards.
    static func commodityKey(for l: ShipperAPI.MyLoad) -> String {
        if l.hazmat {
            switch (l.hazmatClass ?? "").prefix(1) {
            case "1": return "hazmat_explosive"
            case "2": return "hazmat_gas"
            case "3": return "hazmat_flammable"
            case "7": return "hazmat_radioactive"
            case "8": return "hazmat_corrosive"
            // Classes 4-6 / 9 have no dedicated rate-table key; flammable is
            // the closest hazmat rate and the picker stays user-editable.
            default:  return "hazmat_flammable"
            }
        }
        let e = l.equipment.lowercased(), p = l.product.lowercased()
        if e.contains("reefer") || e.contains("refriger") || p.contains("frozen") { return "food_reefer" }
        if p.contains("pharma") || p.contains("medical") { return "pharma" }
        if p.contains("electronic") { return "electronics" }
        if p.contains("crude") || p.contains("petroleum") || p.contains("oil") { return "crude_oil" }
        if p.contains("machin") { return "machinery" }
        if p.contains("auto") || p.contains("vehicle") { return "auto" }
        if p.contains("food") || p.contains("grain") || p.contains("produce") { return "food_dry" }
        return "general"
    }

    // MARK: Trip fields (instructive placeholders — no dev literals)

    private var inputFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            field("COMMODITY") {
                Picker("", selection: $commodity) {
                    ForEach(PerLoadCommodity.all, id: \.key) { Text($0.label).tag($0.key) }
                }.pickerStyle(.menu).tint(palette.textPrimary)
            }
            VStack(alignment: .leading, spacing: 6) {
                field("DECLARED CARGO VALUE (USD)") {
                    TextField("Declared value", text: $cargoValue)
                        .keyboardType(.numberPad).foregroundStyle(palette.textPrimary)
                }
                if valuePrefilledFromRate {
                    Text("Seeded from the load's line-haul rate — adjust to the cargo's declared value.")
                        .font(EType.micro).foregroundStyle(palette.textTertiary)
                }
            }
            field("ORIGIN") {
                TextField("Pickup city, ST", text: $origin).foregroundStyle(palette.textPrimary)
            }
            field("DESTINATION") {
                TextField("Delivery city, ST", text: $destination).foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: Live indicative premium (gradient-rim card, mirrors the 297 hero)

    private func quoteResultCard(_ q: PerLoadQuote) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                Text("INDICATIVE PREMIUM · \(q.policyType.uppercased())")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(LinearGradient.diagonal)
                    .opacity(0.9)
            }
            Text(currency(q.totalPremium))
                .font(.system(size: 34, weight: .bold)).monospacedDigit()
                .foregroundStyle(LinearGradient.diagonal)
            Rectangle().fill(palette.textTertiary.opacity(0.08)).frame(height: 1)
            line("Base premium", currency(q.premium))
            if q.hazmatSurcharge > 0 { line("Hazmat surcharge", currency(q.hazmatSurcharge)) }
            if q.reeferSurcharge > 0 { line("Reefer surcharge", currency(q.reeferSurcharge)) }
            if q.highValueSurcharge > 0 { line("High-value surcharge", currency(q.highValueSurcharge)) }
            line("Coverage", currency(q.coverage))
            line("Deductible", currency(q.deductible))
            if let v = q.validUntil, let d = ShipperCargoInsurance.parseDate(v) {
                Text("Valid until \(d.formatted(date: .abbreviated, time: .shortened))")
                    .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.85), lineWidth: 1.5)
        )
    }

    // MARK: CTA — active gradient "Lock quote", never a dead gray slab

    @ViewBuilder
    private var lockCTA: some View {
        if let q = quote {
            CTAButton(
                title: "Lock quote",
                action: {
                    onQuoted(q, PerLoadQuoteInputs(
                        commodityType: commodity, cargoValue: cargoValueInt,
                        coverageAmount: cargoValueInt, origin: origin,
                        destination: destination,
                        loadId: pickedLoadId, loadNumber: pickedLoadNumber))
                    dismiss()
                },
                trailingIcon: "lock.fill",
                isLoading: loading
            )
        } else if loading {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("Pricing with EusoShield…")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Space.s2)
        } else {
            Text("Enter declared value, pickup, and delivery — the indicative premium prices live as you type.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func line(_ l: String, _ v: String) -> some View {
        HStack { Text(l).font(EType.caption).foregroundStyle(palette.textSecondary); Spacer()
            Text(v).font(EType.caption.monospaced()).foregroundStyle(palette.textPrimary) }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            content()
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
                .background(RoundedRectangle(cornerRadius: Radius.md).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    /// Debounced live pricing — `.task(id: quoteKey)` re-arms on every input
    /// change, sleeps 600 ms, then fires the REAL `insurance.getPerLoadQuote`
    /// mutation. Only the settled inputs ever reach the server; a stale round
    /// never overwrites a newer one.
    private func debouncedQuote() async {
        quoteRound &+= 1
        let round = quoteRound
        guard canQuote else {
            quote = nil; errorText = nil; loading = false
            return
        }
        loading = true; errorText = nil
        defer { if round == quoteRound { loading = false } }
        do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
        struct QuoteIn: Encodable {
            let cargoValue: Int; let commodityType: String; let coverageAmount: Int
            let origin: String; let destination: String
        }
        do {
            let q: PerLoadQuote = try await EusoTripAPI.shared.mutation(
                "insurance.getPerLoadQuote",
                input: QuoteIn(cargoValue: cargoValueInt, commodityType: commodity,
                               coverageAmount: cargoValueInt, origin: origin, destination: destination)
            )
            if round == quoteRound, !Task.isCancelled { quote = q }
        } catch {
            if round == quoteRound, !Task.isCancelled, !(error is CancellationError) {
                errorText = error.localizedDescription
                quote = nil
            }
        }
    }

    private func currency(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        f.maximumFractionDigits = v.rounded() == v ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Request COI sheet (insurance.requestCertificate)

private struct RequestCOISheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) var dismiss
    let onRequested: (RequestCertificateResult) -> Void

    @State private var holderName = ""
    @State private var holderEmail = ""
    @State private var holderAddress = ""
    @State private var additionalInsured = false
    @State private var waiverOfSubrogation = false
    @State private var loading = false
    @State private var errorText: String? = nil

    private var canSubmit: Bool { !holderName.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack {
                    Text("Request certificate").font(EType.h2).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Close").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
                    }.buttonStyle(.plain)
                }
                Text("A certificate of insurance (COI) will be issued to the holder you name below, listing your active coverage.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)

                field("CERTIFICATE HOLDER NAME") {
                    TextField("Certificate holder name", text: $holderName).foregroundStyle(palette.textPrimary)
                }
                field("HOLDER EMAIL") {
                    TextField("Holder email", text: $holderEmail)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        .foregroundStyle(palette.textPrimary)
                }
                field("HOLDER ADDRESS") {
                    TextField("Street, city, ST", text: $holderAddress).foregroundStyle(palette.textPrimary)
                }
                Toggle(isOn: $additionalInsured) {
                    Text("Additional insured endorsement").font(EType.caption).foregroundStyle(palette.textPrimary)
                }.tint(Brand.success)
                Toggle(isOn: $waiverOfSubrogation) {
                    Text("Waiver of subrogation").font(EType.caption).foregroundStyle(palette.textPrimary)
                }.tint(Brand.success)

                if let e = errorText { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }

                Button { Task { await submit() } } label: {
                    HStack(spacing: 6) {
                        if loading { ProgressView().scaleEffect(0.8) }
                        Text(loading ? "Requesting…" : "Request COI").font(EType.bodyStrong).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, Space.s3)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(canSubmit ? AnyShapeStyle(LinearGradient.diagonal)
                                                         : AnyShapeStyle(palette.textTertiary.opacity(0.4))))
                }.buttonStyle(.plain).disabled(!canSubmit || loading)
            }
            .padding(Space.s4)
        }
        .background(palette.bgPrimary)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            content()
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
                .background(RoundedRectangle(cornerRadius: Radius.md).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func submit() async {
        loading = true; errorText = nil
        defer { loading = false }
        // NOTE: we deliberately do NOT send policyIds — the server currently
        // ignores that field (PREMORTEM #5), so sending it would imply a policy
        // linkage the backend won't persist. Holder fields only.
        struct CertIn: Encodable {
            let holderName: String; let holderAddress: String?; let holderEmail: String?
            let additionalInsuredEndorsement: Bool; let waiverOfSubrogation: Bool
        }
        do {
            let result: RequestCertificateResult = try await EusoTripAPI.shared.mutation(
                "insurance.requestCertificate",
                input: CertIn(holderName: holderName.trimmingCharacters(in: .whitespaces),
                              holderAddress: holderAddress.isEmpty ? nil : holderAddress,
                              holderEmail: holderEmail.isEmpty ? nil : holderEmail,
                              additionalInsuredEndorsement: additionalInsured,
                              waiverOfSubrogation: waiverOfSubrogation)
            )
            if result.success {
                onRequested(result)
                dismiss()
            } else {
                errorText = "Request did not complete. Please try again."
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview("297 Cargo Insurance · Dark") {
    ShipperCargoInsurance()
        .environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPrimary)
        .preferredColorScheme(.dark)
}

#Preview("297 Cargo Insurance · Light") {
    ShipperCargoInsurance()
        .environment(\.palette, Theme.light)
        .background(Theme.light.bgPrimary)
        .preferredColorScheme(.light)
}
#endif
