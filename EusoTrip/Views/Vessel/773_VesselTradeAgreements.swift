//
//  773_VesselTradeAgreements.swift
//  EusoTrip — Vessel Operator · Trade Agreement Eligibility.
//
//  Verbatim port of wireframe 773 (06 Vessel · Dark) — a purpose-built
//  ELIGIBILITY-MATRIX: a PROGRAM × (rate · certificate-of-origin ·
//  qualification) grid that ends in an effective-landed-duty sum row.
//  Answers "which duty-preference program does this HTS + origin actually
//  qualify for, and what's the cheapest lawful entry" — comparing programs
//  rather than a single duty calc.
//
//  Endpoints (server/routers/vesselShipments.ts):
//    getTradeAgreements (:3351 · {htsCode, originCountry} → TradeAgreement[])
//    getDutyEstimate    (:3336 · {htsCode, declaredValue, countryOfOrigin}
//                        → DutyEstimate {dutyRate, dutyAmount, additionalDuties,
//                          totalFees, totalLandedCost, applicablePrograms})
//  Both are Avalara-backed and may return null when the classifier is offline
//  — decoded optional, surfaced honestly (no fabricated rate).
//

import SwiftUI

struct VesselTradeAgreementsScreen: View {
    let theme: Theme.Palette
    // Fixed classification context for this shipment (HTS 0810 berries · CN → US).
    var htsCode: String = "0810"
    var originCountry: String = "CN"
    var declaredValue: Double = 184_200

    var body: some View {
        Shell(theme: theme) {
            VesselTradeAgreementsBody(htsCode: htsCode, originCountry: originCountry, declaredValue: declaredValue)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct TradeAgreement773: Decodable, Identifiable {
    var id: String { agreementCode.isEmpty ? agreementName : agreementCode }
    let agreementName: String
    let agreementCode: String
    let preferentialRate: Double
    let standardRate: Double
    let savings: Double
    let requiresCertificateOfOrigin: Bool
    let certificateType: String?
    let conditions: [String]

    private enum CodingKeys: String, CodingKey {
        case agreementName, agreementCode, preferentialRate, standardRate
        case savings, requiresCertificateOfOrigin, certificateType, conditions
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        agreementName    = (try? c.decode(String.self, forKey: .agreementName)) ?? "Program"
        agreementCode    = (try? c.decode(String.self, forKey: .agreementCode)) ?? ""
        preferentialRate = Dec773.d(c, .preferentialRate)
        standardRate     = Dec773.d(c, .standardRate)
        savings          = Dec773.d(c, .savings)
        requiresCertificateOfOrigin = (try? c.decode(Bool.self, forKey: .requiresCertificateOfOrigin)) ?? false
        certificateType  = try? c.decode(String.self, forKey: .certificateType)
        conditions       = (try? c.decode([String].self, forKey: .conditions)) ?? []
    }
}

private struct DutyEstimate773: Decodable {
    let dutyRate: Double
    let dutyAmount: Double
    let totalFees: Double
    let totalLandedCost: Double
    let currency: String
    let additionalDuties: [AddDuty773]
    let applicablePrograms: [String]

    private enum CodingKeys: String, CodingKey {
        case dutyRate, dutyAmount, totalFees, totalLandedCost, currency, additionalDuties, applicablePrograms
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        dutyRate         = Dec773.d(c, .dutyRate)
        dutyAmount       = Dec773.d(c, .dutyAmount)
        totalFees        = Dec773.d(c, .totalFees)
        totalLandedCost  = Dec773.d(c, .totalLandedCost)
        currency         = (try? c.decode(String.self, forKey: .currency)) ?? "USD"
        additionalDuties = (try? c.decode([AddDuty773].self, forKey: .additionalDuties)) ?? []
        applicablePrograms = (try? c.decode([String].self, forKey: .applicablePrograms)) ?? []
    }
    /// Effective ad-valorem % = base duty + Σ additional (e.g. Section 301).
    var effectiveRate: Double { dutyRate + additionalDuties.reduce(0) { $0 + $1.rate } }
}

private struct AddDuty773: Decodable, Identifiable {
    var id: String { type }
    let type: String
    let rate: Double
    let amount: Double
    private enum CodingKeys: String, CodingKey { case type, rate, amount }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        type   = (try? c.decode(String.self, forKey: .type)) ?? "Additional duty"
        rate   = Dec773.d(c, .rate)
        amount = Dec773.d(c, .amount)
    }
}

private enum Dec773 {
    static func d<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> Double {
        if let v = try? c.decode(Double.self, forKey: k) { return v }
        if let s = try? c.decode(String.self, forKey: k), let v = Double(s) { return v }
        return 0
    }
}

// MARK: - Body

private struct VesselTradeAgreementsBody: View {
    @Environment(\.palette) private var palette
    let htsCode: String
    let originCountry: String
    let declaredValue: Double

    @State private var agreements: [TradeAgreement773] = []
    @State private var duty: DutyEstimate773? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var dutyUnavailable = false
    @State private var agreementsUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · TRADE AGREEMENTS",
                caption: "HTS \(htsCode) · \(originCountry)",
                title: "Trade Agreements",
                idText: "VES-260524-C108D4"
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else {
                    hero
                    matrixSection
                    esang
                    ctaPair
                }
                Color.clear.frame(height: Space.s6)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // Effective-duty hero band
    private var hero: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("HTS \(htsCode) · BERRIES")
                        .font(.system(size: 10, weight: .bold)).tracking(0.3)
                        .foregroundStyle(Color(hex: 0x90A4AE))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.rail.opacity(0.14)))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("DUTY OWED").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(dutyOwedText)
                            .font(.system(size: 20, weight: .bold)).monospacedDigit()
                            .foregroundStyle(dutyUnavailable ? palette.textSecondary : Brand.warning)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text(effectiveRateText)
                        .font(.system(size: 30, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("effective duty · \(originCountry) origin → US")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text("declared \(Fmt773.money(declaredValue)) · \(qualifyingLine)")
                            .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
    }

    private var dutyOwedText: String { dutyUnavailable ? "—" : Fmt773.money(duty?.totalFees ?? 0) }
    private var effectiveRateText: String {
        dutyUnavailable ? "—" : String(format: "%.1f%%", duty?.effectiveRate ?? 0)
    }
    private var qualifyingLine: String {
        let eligible = agreements.filter { $0.savings > 0 }
        if agreementsUnavailable { return "program lookup offline" }
        return eligible.isEmpty ? "no preference qualifies" : "\(eligible.count) preference program(s) qualify"
    }

    // Program eligibility matrix
    private var matrixSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            SectionLabel773(text: "PROGRAM ELIGIBILITY", endpoint: "getTradeAgreements")
            VStack(spacing: 0) {
                header
                Divider().overlay(palette.borderFaint)
                if agreements.isEmpty {
                    if agreementsUnavailable {
                        VesselGapNote(text: "Avalara trade-agreement lookup returned no data for HTS \(htsCode)/\(originCountry). Rows populate when the classifier is reachable.")
                            .padding(.vertical, Space.s3)
                    } else {
                        Text("No preference programs found for this classification.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Space.s4)
                    }
                } else {
                    ForEach(Array(agreements.enumerated()), id: \.element.id) { idx, a in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        programRow(a)
                    }
                }
                // Effective landed-duty sum row
                effectiveRow
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var header: some View {
        HStack {
            Text("PROGRAM").font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("RATE").font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary).frame(width: 56, alignment: .trailing)
            Text("COO").font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary).frame(width: 34, alignment: .center)
            Text("STATUS").font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary).frame(width: 66, alignment: .trailing)
        }
        .padding(.bottom, Space.s2)
    }

    private func programRow(_ a: TradeAgreement773) -> some View {
        let eligible = a.savings > 0
        let rate = eligible ? a.preferentialRate : a.standardRate
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(a.agreementName).font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(subLine(a))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(String(format: "%.1f%%", rate))
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(eligible ? Brand.success : palette.textPrimary)
                .frame(width: 56, alignment: .trailing)
            Group {
                if a.requiresCertificateOfOrigin {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.success)
                } else {
                    Text("—").font(.system(size: 12)).foregroundStyle(palette.textTertiary)
                }
            }.frame(width: 34, alignment: .center)
            StatusPill(text: eligible ? "ELIGIBLE" : "N/A", kind: eligible ? .success : .neutral)
                .frame(width: 66, alignment: .trailing)
        }
        .padding(.vertical, Space.s3)
    }

    private func subLine(_ a: TradeAgreement773) -> String {
        if let cond = a.conditions.first { return cond }
        if let cert = a.certificateType, !cert.isEmpty { return "requires \(cert)" }
        return a.agreementCode.isEmpty ? "preference program" : a.agreementCode
    }

    private var effectiveRow: some View {
        HStack {
            Text("Effective landed duty · getDutyEstimate")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Text(effectiveRateText)
                .font(.system(size: 18, weight: .bold)).monospacedDigit()
                .foregroundStyle(LinearGradient.diagonal)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Brand.blue.opacity(0.06)))
        .padding(.top, Space.s3)
    }

    private var esang: some View {
        let eligible = agreements.contains { $0.savings > 0 }
        return EsangAdvisory773(
            title: eligible ? "A preference program qualifies — file the COO to claim it"
                            : "Transship via Manzanillo MXZLO to claim T-MEC",
            message: eligible ? "Attaching the certificate of origin drops the effective duty on this entry"
                              : "Substantial-transformation test → 0% + clears the Section 301 surcharge"
        )
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "File certificate", action: {})
            Button {} label: {
                Text("HTS detail").font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 140, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
            }.buttonStyle(.plain)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 84)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 300)
        }
    }

    // MARK: - Networking

    private func load() async {
        loading = true; loadError = nil; dutyUnavailable = false; agreementsUnavailable = false
        struct AgIn: Encodable { let htsCode: String; let originCountry: String }
        struct DuIn: Encodable { let htsCode: String; let declaredValue: Double; let countryOfOrigin: String }
        do {
            async let agTask: [TradeAgreement773]? = EusoTripAPI.shared.query(
                "vesselShipments.getTradeAgreements",
                input: AgIn(htsCode: htsCode, originCountry: originCountry))
            async let duTask: DutyEstimate773? = EusoTripAPI.shared.query(
                "vesselShipments.getDutyEstimate",
                input: DuIn(htsCode: htsCode, declaredValue: declaredValue, countryOfOrigin: originCountry))
            let ag = try await agTask
            let du = try await duTask
            self.agreements = ag ?? []
            self.agreementsUnavailable = (ag == nil)
            self.duty = du
            self.dutyUnavailable = (du == nil)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

private enum Fmt773 {
    static func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v)) ?? String(Int(v)))
    }
}

private struct SectionLabel773: View {
    @Environment(\.palette) private var palette
    let text: String; var endpoint: String? = nil
    var body: some View {
        HStack {
            Text(text).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            Spacer()
            if let endpoint { Text(endpoint).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(palette.textTertiary) }
        }
    }
}

private struct EsangAdvisory773: View {
    @Environment(\.palette) private var palette
    let title: String; let message: String
    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

#Preview("773 · Trade Agreements · Night") { VesselTradeAgreementsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("773 · Trade Agreements · Light") { VesselTradeAgreementsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
