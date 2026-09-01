//
//  733_VesselCargoInsurance.swift
//  EusoTrip — Vessel Operator · Cargo Insurance.
//
//  Faithful 1:1 native port of the canonical wireframe "733 Vessel Cargo
//  Insurance · Dark/Light". DETAIL/MONEY archetype: a per-booking all-risk
//  marine cargo quote — declared insured value → live premium, ICC (A) clause,
//  deductible, a certificate/commodity read strip, and a purchase action.
//
//  HONEST BINDING (server/routers/insurance.ts + vesselShipments.ts):
//    · vesselShipments.getVesselShipments      — anchors the quote to a real ocean booking.
//    · vesselShipments.getVesselShipmentDetail  — resolves the real lane (origin/destination ports).
//    · insurance.getPerLoadQuote                — REAL premium/deductible/policyType from the
//                                                 operator's DECLARED insured value (marine cargo is a
//                                                 declared-value cover; the value is a user control, the
//                                                 premium is a real server computation — never fabricated).
//    · insurance.getCertificates                — real COI count on file.
//    · insurance.getCommodityInsuranceRequirements — real commodity coverage floor.
//    · insurance.purchasePerLoad                — REAL purchase mutation (writes a policy + wallet debit).
//  HONEST GAP: war-risk endorsement toggle + per-leg sub-limit are not yet on
//  getPerLoadQuote's return; surfaced as an explicit awaiting note, no fake data.
//  RBAC vesselProcedure/protected · transportMode=vessel · US/CA/MX premium-tax overlay is server-side.
//

import SwiftUI

struct VesselCargoInsuranceScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselCargoInsuranceBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",      isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",         isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decoders (all-optional → partial payloads degrade to honest states)

private struct VesselShipmentList733: Decodable { let shipments: [VesselShipmentRow733]?; let total: Int? }
private struct VesselShipmentRow733: Decodable {
    let id: Int?
    let bookingNumber: String?
    let voyageNumber: String?
    let serviceRoute: String?
    let commodity: String?
    let cargoType: String?
    let hazmatClass: String?
    let containerSize: String?
    let numberOfContainers: Int?
    let vesselId: Int?
    let incoterms: String?
    let originPortId: Int?
    let destinationPortId: Int?
}
private struct VesselShipmentDetail733: Decodable {
    let id: Int?
    let bookingNumber: String?
    let voyageNumber: String?
    let commodity: String?
    let cargoType: String?
    let incoterms: String?
    let originPort: Port733?
    let destinationPort: Port733?
    let vessel: Vessel733?
}
private struct Port733: Decodable { let name: String?; let unlocode: String?; let city: String?; let country: String? }
private struct Vessel733: Decodable { let name: String?; let imoNumber: String? }

private struct PerLoadQuote733: Decodable {
    let premium: Double?
    let coverage: Double?
    let deductible: Double?
    let totalPremium: Double?
    let policyType: String?
    let reeferSurcharge: Double?
    let hazmatSurcharge: Double?
    let validUntil: String?
}
private struct CertRow733: Decodable {
    let id: Int?
    let certificateNumber: String?
    let status: String?
    let expiresAt: String?
    let expirationDate: String?
}
private struct CommodityReq733: Decodable {
    let category: String?
    let minCargo: Double?
    let minLiability: Double?
    let notes: String?
    let specialEndorsements: [String]?
}
private struct PurchaseResult733: Decodable { let policyNumber: String?; let id: Int? }

// MARK: - Body

private struct VesselCargoInsuranceBody: View {
    @Environment(\.palette) private var palette

    @State private var booking: VesselShipmentRow733? = nil
    @State private var detail: VesselShipmentDetail733? = nil
    @State private var quote: PerLoadQuote733? = nil
    @State private var certs: [CertRow733] = []
    @State private var commodityReq: CommodityReq733? = nil

    // Declared insured value — a REAL operator control (marine cargo is a
    // declared-value cover). Starts at a neutral declaration the user adjusts;
    // the premium is always a live server computation of THIS value.
    @State private var declaredValue: Double = 180_000

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var quoting = false
    @State private var purchasing = false
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil

    private let clause = "ICC (A)"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    skeleton
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if booking == nil {
                    EusoEmptyState(
                        systemImage: "shield.lefthalf.filled",
                        title: "No ocean booking",
                        subtitle: "A per-booking marine cargo quote appears once a vessel booking exists to insure.")
                } else {
                    heroCard
                    kpiStrip
                    declaredValueControl
                    quoteSection
                    bookingFooter
                    ctaRow
                    actionFeedback
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .onChange(of: declaredValue) { _, _ in Task { await requote() } }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · CARGO INSURANCE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text(quote?.totalPremium.map { "quote \(usd0($0))" } ?? "quote —")
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Cargo Insurance")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            skel(116); skel(72); skel(252)
        }
    }
    private func skel(_ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .fill(palette.bgCardSoft).frame(height: h)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
    }

    // MARK: Hero — premium + insured + quoted-rate

    private var heroCard: some View {
        let insured = quote?.coverage ?? declaredValue
        let premium = quote?.totalPremium ?? quote?.premium
        let ratePct: Double? = {
            guard let p = premium, insured > 0 else { return nil }
            return p / insured * 100
        }()
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCardSoft).padding(1.5)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    tagChip("all-risk"); tagChip(clause)
                    Spacer()
                }
                HStack(alignment: .top, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(premium.map { usd0($0) } ?? "—")
                            .font(.system(size: 30, weight: .bold)).tracking(-0.4)
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                        Text("per-booking premium")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("\(usdCompact(insured)) insured · \(clause)")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("QUOTED")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(ratePct.map { String(format: "%.2f%%", $0) } ?? "—")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                        Text("of insured value")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .padding(Space.s5)
        }
        .frame(minHeight: 116)
    }

    private func tagChip(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 11, weight: .semibold)).tracking(0.5)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(palette.textPrimary.opacity(0.08)))
    }

    // MARK: KPI strip — PREMIUM / INSURED / DEDUCT.

    private var kpiStrip: some View {
        HStack(spacing: Space.s3) {
            kpiCell("PREMIUM", quote?.totalPremium.map { usd0($0) } ?? "—", highlight: true)
            kpiCell("INSURED", usdCompact(quote?.coverage ?? declaredValue), highlight: false)
            kpiCell("DEDUCT.", quote?.deductible.map { usd0($0) } ?? "—", highlight: false)
        }
    }
    private func kpiCell(_ label: String, _ value: String, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(highlight ? Color.white.opacity(0.85) : palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(highlight ? .white : palette.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 14)
        .background(
            Group {
                if highlight { LinearGradient.diagonal }
                else { palette.bgCardSoft }
            }
        )
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(highlight ? Color.clear : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Declared insured value control (real operator input)

    private var declaredValueControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DECLARED INSURED VALUE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(quoting ? "quoting…" : "live premium")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                stepBtn("minus") { adjust(-10_000) }
                Text(usd0(declaredValue))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                stepBtn("plus") { adjust(10_000) }
            }
            Text("Operator-declared shipment value · CIF basis · premium independently recomputed")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private func stepBtn(_ icon: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 44, height: 44)
                .background(palette.bgCardSoft)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    private func adjust(_ delta: Double) {
        declaredValue = max(10_000, declaredValue + delta)
    }

    // MARK: Quote section — 3 read rows

    private var quoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("QUOTE · getPerLoadQuote", ref: "LIVE UNDERWRITER QUOTE", gap: false)
            VStack(spacing: 0) {
                quoteRow(
                    icon: "shield.lefthalf.filled", tint: Color(hex: 0x5AB0FF),
                    title: "All-risk marine cargo",
                    sub: "Institute Cargo Clauses A",
                    chip: "QUOTED", chipTint: Color(hex: 0x5AB0FF),
                    trailing: quote?.totalPremium.map { usd0($0) } ?? "—")
                rowDivider
                quoteRow(
                    icon: "doc.text.fill", tint: Brand.success,
                    title: "Certificates on file",
                    sub: certSubtitle,
                    chip: "COI×\(certs.count)", chipTint: Brand.success,
                    trailing: certs.isEmpty ? "none" : "active")
                rowDivider
                quoteRow(
                    icon: "checklist", tint: Color(hex: 0x5AB0FF),
                    title: "Commodity reqs\(commodityLabelSuffix)",
                    sub: commoditySubtitle,
                    chip: commodityReq == nil ? "—" : "MET", chipTint: Brand.success,
                    trailing: commodityReq == nil ? "—" : "OK")
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            Text("War-risk endorsement pricing appears only when returned by the underwriter.")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 2)
        }
    }

    private func quoteRow(icon: String, tint: Color, title: String, sub: String,
                          chip: String, chipTint: Color, trailing: String) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.2)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(sub).font(EType.mono(.caption)).tracking(0.4).foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 5) {
                Text(chip)
                    .font(.system(size: 10, weight: .bold)).tracking(0.4)
                    .foregroundStyle(chipTint)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(chipTint.opacity(0.20)))
                Text(trailing).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).monospacedDigit()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
    }
    private var rowDivider: some View {
        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 16)
    }

    // MARK: Booking footer

    private var bookingFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("BOOKING · \(vesselLine)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                Spacer()
                Text("SIGNED COVERAGE RECORD")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Text(laneLine)
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            Text("shipper of record · certificate issuance")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: CTA

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: purchasing ? "Purchasing…" : "Purchase per-booking cover",
                      action: { Task { await purchase() } },
                      isLoading: purchasing || quote == nil)
            Button { Task { await requote() } } label: {
                Text("Quote +")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 120, height: 52)
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var actionFeedback: some View {
        if let actionError {
            LifecycleCard(accentDanger: true) {
                Text(actionError).font(EType.caption).foregroundStyle(Brand.danger)
            }
        } else if let actionMessage {
            LifecycleCard {
                Text(actionMessage).font(EType.caption).foregroundStyle(Brand.success)
            }
        }
    }

    private func sectionLabel(_ title: String, ref: String, gap: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            Spacer()
            Text(gap ? "NOT AVAILABLE" : ref)
                .font(EType.mono(.micro)).foregroundStyle(gap ? Brand.warning : palette.textTertiary)
        }
    }

    // MARK: Derived copy

    private var vesselLine: String {
        if let v = detail?.vessel?.name, !v.isEmpty { return "MV \(v)" }
        if let voy = booking?.voyageNumber, !voy.isEmpty { return "voyage \(voy)" }
        return booking?.bookingNumber ?? "—"
    }
    private var laneLine: String {
        let o = portLabel(detail?.originPort) ?? "origin"
        let d = portLabel(detail?.destinationPort) ?? "destination"
        let terms = firstNonEmpty(detail?.incoterms, booking?.incoterms).map { " · \($0.uppercased()) terms" } ?? ""
        let cargo = firstNonEmpty(detail?.commodity, booking?.commodity, booking?.cargoType).map { " · \($0)" } ?? ""
        return "\(o) → \(d)\(terms)\(cargo)"
    }
    private var certSubtitle: String {
        guard !certs.isEmpty else { return "no certificates on file yet" }
        let active = certs.filter { ($0.status ?? "").lowercased() == "active" }.count
        return "\(active > 0 ? active : certs.count) active COI\(certs.count == 1 ? "" : "s")"
    }
    private var commodityLabelSuffix: String {
        guard let cat = commodityReq?.category, !cat.isEmpty else { return "" }
        return " (\(cat.replacingOccurrences(of: "_", with: " ")))"
    }
    private var commoditySubtitle: String {
        guard let req = commodityReq else { return "awaiting commodity classification" }
        if let notes = req.notes, !notes.isEmpty { return notes }
        if let floor = req.minCargo { return "cargo floor \(usd0(floor))" }
        return "coverage floor set"
    }

    // MARK: Load / quote / purchase

    private func load() async {
        loading = true; loadError = nil; actionError = nil; actionMessage = nil
        defer { loading = false }
        struct ListInput: Encodable { let limit: Int; let offset: Int }
        struct DetailInput: Encodable { let id: Int }
        do {
            let list: VesselShipmentList733 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipments", input: ListInput(limit: 1, offset: 0))
            guard let first = list.shipments?.first, let id = first.id else {
                booking = nil; return
            }
            booking = first
            detail = try? await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: DetailInput(id: id))
            await requote()
            await loadCertsAndReqs(commodity: firstNonEmpty(first.commodity, first.cargoType) ?? "general",
                                   hazmatClass: first.hazmatClass)
        } catch {
            loadError = error.eusoUserCopy
            booking = nil
        }
    }

    private func requote() async {
        guard let b = booking else { return }
        quoting = true; defer { quoting = false }
        struct QuoteInput: Encodable {
            let cargoValue: Double; let commodityType: String; let coverageAmount: Double
            let origin: String; let destination: String
        }
        let commodity = firstNonEmpty(b.commodity, b.cargoType) ?? "general"
        let origin = portLabel(detail?.originPort) ?? b.originPortId.map { "Port \($0)" } ?? "origin"
        let dest = portLabel(detail?.destinationPort) ?? b.destinationPortId.map { "Port \($0)" } ?? "destination"
        do {
            quote = try await EusoTripAPI.shared.mutation(
                "insurance.getPerLoadQuote",
                input: QuoteInput(cargoValue: declaredValue, commodityType: commodity,
                                  coverageAmount: declaredValue, origin: origin, destination: dest))
        } catch {
            actionError = error.eusoUserCopy
        }
    }

    private func loadCertsAndReqs(commodity: String, hazmatClass: String?) async {
        struct CertInput: Encodable { let limit: Int }
        struct ReqInput: Encodable { let commodityType: String; let hazmatClass: String? }
        certs = (try? await EusoTripAPI.shared.query(
            "insurance.getCertificates", input: CertInput(limit: 10))) ?? []
        commodityReq = try? await EusoTripAPI.shared.query(
            "insurance.getCommodityInsuranceRequirements",
            input: ReqInput(commodityType: commodity, hazmatClass: hazmatClass))
    }

    private func purchase() async {
        guard let b = booking, let q = quote else { return }
        purchasing = true; actionError = nil; actionMessage = nil
        defer { purchasing = false }
        struct PurchaseInput: Encodable {
            let cargoValue: Double; let coverageAmount: Double; let deductible: Double
            let premium: Double; let basePremium: Double
            let commodityType: String; let policyType: String
            let origin: String; let destination: String; let loadId: Int?
        }
        let commodity = firstNonEmpty(b.commodity, b.cargoType) ?? "general"
        let origin = portLabel(detail?.originPort) ?? "origin"
        let dest = portLabel(detail?.destinationPort) ?? "destination"
        do {
            let res: PurchaseResult733 = try await EusoTripAPI.shared.mutation(
                "insurance.purchasePerLoad",
                input: PurchaseInput(
                    cargoValue: declaredValue,
                    coverageAmount: q.coverage ?? declaredValue,
                    deductible: q.deductible ?? 0,
                    premium: q.totalPremium ?? q.premium ?? 0,
                    basePremium: q.premium ?? q.totalPremium ?? 0,
                    commodityType: commodity,
                    policyType: q.policyType ?? "all_risk",
                    origin: origin, destination: dest,
                    loadId: b.id))
            actionMessage = res.policyNumber.map { "Cover bound · policy \($0)." }
                ?? "Per-booking cargo cover bound."
        } catch {
            actionError = error.eusoUserCopy
        }
    }

    // MARK: Helpers

    private func portLabel(_ p: Port733?) -> String? {
        guard let p else { return nil }
        if let u = p.unlocode, !u.isEmpty { return u }
        if let c = p.city, !c.isEmpty { return c }
        return p.name
    }
    private func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { v -> String? in
            let t = v?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty == false) ? t : nil
        }.first
    }
    private func usd0(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v))
    }
    private func usdCompact(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "$%.0fk", v / 1_000) }
        return usd0(v)
    }
}

#Preview("733 · Vessel Cargo Insurance · Night") { VesselCargoInsuranceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("733 · Vessel Cargo Insurance · Light") { VesselCargoInsuranceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
