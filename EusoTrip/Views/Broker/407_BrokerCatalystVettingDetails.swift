//
//  407_BrokerCatalystVettingDetails.swift
//  EusoTrip — Broker · Per-applicant vetting drill-down (brick 407).
//
//  iOS port of web `CatalystVettingDetails.tsx`. Reached from
//  406_BrokerCatalystVetting (the list) when the broker taps a row.
//  Pulls REAL data from `catalysts.{getById, getCSAScores,
//  getInsurance, getLoadHistory, approve, reject}` — getCSAScores
//  was a stub before this commit pair; the paired platform commit
//  upgrades it to real fmcsa_sms_scores lookups via the existing
//  getSafetyScores helper.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire models

private struct CatalystRecord: Decodable, Hashable {
    let id: Int
    let name: String?
    let dotNumber: String?
    let mcNumber: String?
    let complianceStatus: String?
    let createdAt: String?
}

private struct CSAScoreRow: Decodable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    let score: Double
    let percentile: Double?
    let threshold: Double?
    let alert: Bool
    let unavailable: Bool?
}

private struct InsuranceDoc: Decodable, Hashable, Identifiable {
    let id: String
    let type: String?
    let name: String?
    let status: String?
    let expiresAt: String?
}

private struct LoadHistoryRow: Decodable, Hashable, Identifiable {
    let id: String
    let loadNumber: String?
    let status: String?
    let pickupCity: String?
    let destCity: String?
    let rate: String?
    let createdAt: String?
}

// MARK: - Screen

struct BrokerCatalystVettingDetailsScreen: View {
    let theme: Theme.Palette
    let catalystId: String

    var body: some View {
        Shell(theme: theme) { DetailsBody(catalystId: catalystId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Loads",    systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Carriers", systemImage: "person.3.fill",   isCurrent: true),
                           NavSlot(label: "Me",       systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct DetailsBody: View {
    @Environment(\.palette) private var palette
    let catalystId: String

    @State private var catalyst: CatalystRecord?
    @State private var csa: [CSAScoreRow] = []
    @State private var insurance: [InsuranceDoc] = []
    @State private var history: [LoadHistoryRow] = []
    @State private var loading: Bool = true
    @State private var error: String?
    @State private var activeTab: Tab = .overview
    @State private var acting: Bool = false
    @State private var ack: String?

    private enum Tab: String, CaseIterable { case overview, csa, insurance, history
        var label: String {
            switch self {
            case .overview:  return "OVERVIEW"
            case .csa:       return "CSA"
            case .insurance: return "INSURANCE"
            case .history:   return "HISTORY"
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let c = catalyst { identityCard(c) }
                tabStrip
                content
                if let m = ack {
                    LifecycleCard(accentGradient: true) {
                        Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                if let err = error {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
                actionButtons
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    // MARK: subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.rectangle.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("BROKER · APPLICANT DETAILS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Vetting details")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Identity + CSA + insurance + load history for a single applicant.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func identityCard(_ c: CatalystRecord) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 6) {
                LifecycleSection(label: (c.name ?? "Applicant").uppercased(), icon: "building.2.fill")
                LifecycleRow(label: "USDOT",   value: dashIfEmpty(c.dotNumber))
                LifecycleRow(label: "MC",      value: dashIfEmpty(c.mcNumber))
                LifecycleRow(label: "Status",  value: (c.complianceStatus ?? "—").capitalized)
                if let a = c.createdAt, !a.isEmpty {
                    LifecycleRow(label: "Applied", value: humanDate(a))
                }
            }
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { activeTab = t } label: {
                    Text(t.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(activeTab == t ? .white : palette.textSecondary)
                        .background(activeTab == t
                            ? AnyShapeStyle(LinearGradient.diagonal)
                            : AnyShapeStyle(palette.bgCard))
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        } else {
            switch activeTab {
            case .overview:  overviewTab
            case .csa:       csaTab
            case .insurance: insuranceTab
            case .history:   historyTab
            }
        }
    }

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT LOADS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            if history.isEmpty {
                Text("No recent loads.").font(EType.caption).foregroundStyle(palette.textTertiary)
            } else {
                ForEach(history.prefix(3)) { l in
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(l.loadNumber ?? l.id).font(EType.body.weight(.bold))
                                Spacer()
                                Text((l.status ?? "—").uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(palette.textSecondary)
                            }
                            Text("\(l.pickupCity ?? "—") → \(l.destCity ?? "—")").font(.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                }
            }
            Text("INSURANCE FILES").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary).padding(.top, 8)
            if insurance.isEmpty {
                Text("No insurance docs on file.").font(EType.caption).foregroundStyle(palette.textTertiary)
            } else {
                ForEach(insurance.prefix(3)) { d in
                    LifecycleRow(label: d.type ?? "Doc", value: d.name ?? "—")
                }
            }
        }
    }

    private var csaTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CSA BASICS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            if csa.isEmpty {
                Text("CSA scores unavailable.").font(EType.caption).foregroundStyle(palette.textTertiary)
            } else {
                ForEach(csa) { row in
                    LifecycleCard(accentDanger: row.alert) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).font(EType.body.weight(.semibold))
                                if row.unavailable == true {
                                    Text("No FMCSA SMS data yet").font(.caption2).foregroundStyle(palette.textTertiary)
                                } else if let t = row.threshold {
                                    Text("Threshold: \(Int(t))%").font(.caption2).foregroundStyle(palette.textTertiary)
                                }
                            }
                            Spacer()
                            if row.unavailable == true {
                                Text("—").font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(palette.textTertiary)
                            } else {
                                Text("\(Int(row.score))%")
                                    .font(.title3.weight(.heavy).monospacedDigit())
                                    .foregroundStyle(row.alert ? Brand.danger : palette.textPrimary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var insuranceTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INSURANCE FILES").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            if insurance.isEmpty {
                EusoEmptyState(systemImage: "doc.text", title: "No insurance docs", subtitle: "Applicant hasn't uploaded insurance filings yet.")
            } else {
                ForEach(insurance) { d in
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name ?? "Document").font(EType.body.weight(.semibold))
                            HStack {
                                Text(d.type ?? "—").font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(palette.textTertiary)
                                Spacer()
                                Text((d.status ?? "—").uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(palette.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LOAD HISTORY").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            if history.isEmpty {
                EusoEmptyState(systemImage: "shippingbox", title: "No history", subtitle: "No prior loads found for this applicant.")
            } else {
                ForEach(history) { l in
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(l.loadNumber ?? l.id).font(EType.body.weight(.bold))
                                Spacer()
                                if let r = l.rate { Text("$\(r)").font(.caption.monospacedDigit().weight(.semibold)) }
                            }
                            Text("\(l.pickupCity ?? "—") → \(l.destCity ?? "—")").font(.caption).foregroundStyle(palette.textSecondary)
                            HStack {
                                Text((l.status ?? "—").uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(palette.textTertiary)
                                Spacer()
                                if let c = l.createdAt { Text(humanDate(c)).font(.caption2).foregroundStyle(palette.textTertiary) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button { Task { await fire(.approve) } } label: {
                HStack(spacing: 6) {
                    if acting { ProgressView().tint(.white).controlSize(.mini) }
                    Text("Approve")
                        .font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.diagonal)
                .foregroundStyle(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(acting)

            Button { Task { await fire(.reject) } } label: {
                Text("Reject")
                    .font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(palette.textPrimary)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(Brand.danger.opacity(0.5))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(acting)
        }
    }

    // MARK: helpers

    private func dashIfEmpty(_ s: String?) -> String {
        let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "—" : t
    }
    private func humanDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter(); out.dateStyle = .medium; return out.string(from: d)
    }

    // MARK: pipeline

    private func loadAll() async {
        loading = true; error = nil
        async let a: Void = loadCatalyst()
        async let b: Void = loadCSA()
        async let c: Void = loadInsurance()
        async let d: Void = loadHistory()
        _ = await (a, b, c, d)
        loading = false
    }

    private func loadCatalyst() async {
        struct In: Encodable { let id: String }
        do {
            catalyst = try await EusoTripAPI.shared.query("catalysts.getById", input: In(id: catalystId))
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
    private func loadCSA() async {
        struct In: Encodable { let catalystId: String }
        do { csa = try await EusoTripAPI.shared.query("catalysts.getCSAScores", input: In(catalystId: catalystId)) } catch { /* */ }
    }
    private func loadInsurance() async {
        struct In: Encodable { let catalystId: String }
        do { insurance = try await EusoTripAPI.shared.query("catalysts.getInsurance", input: In(catalystId: catalystId)) } catch { /* */ }
    }
    private func loadHistory() async {
        struct In: Encodable { let catalystId: String; let limit: Int }
        do { history = try await EusoTripAPI.shared.query("catalysts.getLoadHistory", input: In(catalystId: catalystId, limit: 50)) } catch { /* */ }
    }

    private enum Action { case approve, reject }
    private func fire(_ action: Action) async {
        acting = true; error = nil
        defer { acting = false }
        struct ApproveIn: Encodable { let catalystId: String }
        struct RejectIn: Encodable { let catalystId: String; let reason: String? }
        struct Out: Decodable { let success: Bool?; let catalystId: String? }
        do {
            switch action {
            case .approve:
                let _: Out = try await EusoTripAPI.shared.mutation("catalysts.approve", input: ApproveIn(catalystId: catalystId))
                ack = "Applicant approved."
            case .reject:
                let _: Out = try await EusoTripAPI.shared.mutation("catalysts.reject", input: RejectIn(catalystId: catalystId, reason: nil))
                ack = "Applicant rejected."
            }
            await loadCatalyst()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

#Preview("407 · Details · Dark")  { BrokerCatalystVettingDetailsScreen(theme: Theme.dark,  catalystId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("407 · Details · Light") { BrokerCatalystVettingDetailsScreen(theme: Theme.light, catalystId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
