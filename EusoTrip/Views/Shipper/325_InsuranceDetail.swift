//
//  325_InsuranceDetail.swift
//  EusoTrip — Shipper · Insurance detail (Arc J).
//

import SwiftUI

struct InsuranceDetailScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { InsuranceBody() } nav: { shipperLifecycleNav() }
    }
}

private struct InsuranceCert: Decodable, Hashable {
    let carrier: String?
    let policyNumber: String?
    let coverageType: String?
    let limitUsd: Double?
    let effectiveDate: String?
    let expirationDate: String?
    let pdfUrl: String?
}

private struct InsuranceBody: View {
    @Environment(\.palette) private var palette
    @State private var cert: InsuranceCert? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading insurance…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let c = cert { coiCard(c); ctaRow(c) }
                else { LifecycleCard { Text("No insurance certificate on file.").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "umbrella.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · INSURANCE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Insurance certificate").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func coiCard(_ c: InsuranceCert) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "COI", icon: "shield.checkered")
            LifecycleRow(label: "Carrier",        value: dashIfEmpty(c.carrier))
            LifecycleRow(label: "Policy",         value: dashIfEmpty(c.policyNumber))
            LifecycleRow(label: "Coverage type",  value: dashIfEmpty(c.coverageType))
            LifecycleRow(label: "Limit",          value: usd(c.limitUsd))
            LifecycleRow(label: "Effective",      value: humanISO(c.effectiveDate, format: "MMM d, yyyy"))
            LifecycleRow(label: "Expires",        value: humanISO(c.expirationDate, format: "MMM d, yyyy"))
        }
    }

    private func ctaRow(_ c: InsuranceCert) -> some View {
        if let pdf = c.pdfUrl, !pdf.isEmpty {
            return AnyView(Button {
                if let u = URL(string: pdf) { UIApplication.shared.open(u) }
            } label: {
                Text("Open COI PDF").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain))
        }
        return AnyView(EmptyView())
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let c: InsuranceCert = try await EusoTripAPI.shared.queryNoInput("compliance.getInsurance")
            cert = c
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("325 · Insurance · Night") { InsuranceDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("325 · Insurance · Afternoon") { InsuranceDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
