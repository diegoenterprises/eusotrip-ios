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
//    • BottomNav · WALLET active — supplied by the Shipper surface chrome (this
//      file is a tab destination; the host owns nav + WALLET-selected state,
//      identical to the sibling Shipper wallet screens).
//
//  Data (endpoints exactly as named in the wireframe <desc>, verified live):
//    insurance.getPolicies          (routers/insurance.ts:93)  query  → policy rows
//    insurance.getSummary           (routers/insurance.ts:219) query  → totals (tolerant: array/null → zeros)
//    insurance.getExpiringPolicies  (routers/insurance.ts:191) query  → which policies expire ≤30d
//    insurance.getCertificates      (routers/insurance.ts:442) query  → COIs on file
//    insurance.getPerLoadQuote      (routers/insurance.ts:887) MUTATION → server-priced quote
//    insurance.purchasePerLoad      (routers/insurance.ts:930) MUTATION → buy per-load policy (wallet debit)
//    insurance.requestCertificate   (routers/insurance.ts:468) MUTATION → request a COI
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
                case .error(let e):
                    errorBanner(e)
                case .loaded(let model):
                    heroCard(model)
                    kpiStrip(model.summary)
                    policiesCard(model)
                    perLoadQuoteCard
                    ctaRow
                    certificateLine(model.certificates)
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
            PerLoadQuoteSheet { quote, inputs in
                activeQuote = quote
                activeQuoteInputs = inputs
            }
            .environment(\.palette, palette)
        }
        .sheet(isPresented: $coiSheet) {
            RequestCOISheet { result in
                banner = .success("COI requested · \(result.certificateNumber ?? "pending")")
                Task { await store.refresh() }
            }
            .environment(\.palette, palette)
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
        if cov == "—" { return "\(shipperName) · cargo all-risk · annual" }
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
                    value: s.annualPremium.map(grouped) ?? "—",
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
                Text("\(p.providerName ?? "—") · \(p.policyNumber)")
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
            badgeText((p.status ?? "—").uppercased(), palette.textTertiary)
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
                Text("\(grouped(Double(inp.cargoValue))) declared · \(q.policyType)")
                    .font(EType.caption.monospaced()).foregroundStyle(palette.textSecondary).lineLimit(1)
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
                    destination: inp.destination
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
        return "—"
    }

    private var aggregateText: String {
        let policies = store.state.value?.policies ?? []
        let agg = policies
            .filter { $0.policyType.contains("cargo") }
            .compactMap { money($0.aggregateLimit) }
            .max()
        return agg.map(compact) ?? "—"
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
            Text(err.localizedDescription).font(EType.caption)
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

    @State private var commodity = "food_reefer"
    @State private var origin = ""
    @State private var destination = ""
    @State private var cargoValue = ""
    @State private var loading = false
    @State private var quote: PerLoadQuote? = nil
    @State private var errorText: String? = nil

    private var cargoValueInt: Int { Int(cargoValue.filter(\.isNumber)) ?? 0 }
    private var canQuote: Bool { cargoValueInt > 0 && !origin.isEmpty && !destination.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack {
                    Text("New per-load quote").font(EType.h2).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Close").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
                    }.buttonStyle(.plain)
                }

                field("COMMODITY") {
                    Picker("", selection: $commodity) {
                        ForEach(PerLoadCommodity.all, id: \.key) { Text($0.label).tag($0.key) }
                    }.pickerStyle(.menu).tint(palette.textPrimary)
                }
                field("DECLARED CARGO VALUE (USD)") {
                    TextField("44000", text: $cargoValue)
                        .keyboardType(.numberPad).foregroundStyle(palette.textPrimary)
                }
                field("ORIGIN") {
                    TextField("Los Angeles, CA", text: $origin).foregroundStyle(palette.textPrimary)
                }
                field("DESTINATION") {
                    TextField("Phoenix, AZ", text: $destination).foregroundStyle(palette.textPrimary)
                }

                if let q = quote { quoteResult(q) }
                if let e = errorText {
                    Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                }

                Button { Task { await runQuote() } } label: {
                    HStack(spacing: 6) {
                        if loading { ProgressView().scaleEffect(0.8) }
                        Text(loading ? "Pricing…" : "Get quote").font(EType.bodyStrong).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, Space.s3)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(canQuote ? AnyShapeStyle(LinearGradient.diagonal)
                                                        : AnyShapeStyle(palette.textTertiary.opacity(0.4))))
                }.buttonStyle(.plain).disabled(!canQuote || loading)

                if quote != nil {
                    Button {
                        if let q = quote {
                            onQuoted(q, PerLoadQuoteInputs(commodityType: commodity, cargoValue: cargoValueInt,
                                                           coverageAmount: cargoValueInt, origin: origin, destination: destination))
                            dismiss()
                        }
                    } label: {
                        Text("Use this quote").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            .frame(maxWidth: .infinity).padding(.vertical, Space.s3)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            .padding(Space.s4)
        }
        .background(palette.bgPrimary)
    }

    private func quoteResult(_ q: PerLoadQuote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(q.policyType).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Spacer()
                Text(currency(q.totalPremium)).font(.system(size: 22, weight: .bold)).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
            }
            line("Base premium", currency(q.premium))
            if q.hazmatSurcharge > 0 { line("Hazmat surcharge", currency(q.hazmatSurcharge)) }
            if q.reeferSurcharge > 0 { line("Reefer surcharge", currency(q.reeferSurcharge)) }
            if q.highValueSurcharge > 0 { line("High-value surcharge", currency(q.highValueSurcharge)) }
            line("Coverage", currency(q.coverage))
            line("Deductible", currency(q.deductible))
            if let v = q.validUntil { Text("Valid until \(v)").font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary) }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).eusoCard(radius: Radius.lg)
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

    private func runQuote() async {
        loading = true; errorText = nil
        defer { loading = false }
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
            quote = q
        } catch {
            errorText = error.localizedDescription
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
                    TextField("Acme Receiving LLC", text: $holderName).foregroundStyle(palette.textPrimary)
                }
                field("HOLDER EMAIL") {
                    TextField("ap@acme.com", text: $holderEmail)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        .foregroundStyle(palette.textPrimary)
                }
                field("HOLDER ADDRESS") {
                    TextField("123 Dock St, Phoenix, AZ", text: $holderAddress).foregroundStyle(palette.textPrimary)
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
struct ShipperCargoInsurance_Previews: PreviewProvider {
    static var previews: some View {
        ShipperCargoInsurance()
            .environment(\.palette, Theme.dark)
            .background(Theme.dark.bgPrimary)
            .preferredColorScheme(.dark)
    }
}
#endif
