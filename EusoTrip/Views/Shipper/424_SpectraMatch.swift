//
//  424_SpectraMatch.swift
//  EusoTrip — Shipper · SpectraMatch™ AI crude oil + product identification.
//

import SwiftUI

struct SpectraMatchScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { SpectraMatchBody() } nav: { shipperLifecycleNav() }
    }
}

private struct SpectraResult: Decodable, Hashable {
    let bestMatch: String
    let confidencePct: Int
    let alternates: [String]?
    let api: Double?
    let sulfur: Double?
    let pour: Double?
}

private struct SpectraMatchBody: View {
    @Environment(\.palette) private var palette
    @State private var apiGravity: Double? = nil
    @State private var sulfur: Double? = nil
    @State private var pourPoint: Double? = nil
    @State private var loading = false
    @State private var result: SpectraResult? = nil
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                inputCard
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                if let r = result { resultCard(r) }
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "drop.triangle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · SPECTRAMATCH™").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Identify crude / product").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Enter the spec sheet readings. ESANG cross-references the global crude library to identify the closest match.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inputCard: some View {
        LifecycleCard {
            LifecycleSection(label: "SPEC SHEET", icon: "doc.text")
            field("API gravity (°API)", value: $apiGravity)
            field("Sulfur content (% wt)", value: $sulfur)
            field("Pour point (°F)", value: $pourPoint)
        }
    }

    private func field(_ label: String, value: Binding<Double?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            TextField("", value: value, format: .number).keyboardType(.decimalPad).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func resultCard(_ r: SpectraResult) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "BEST MATCH", icon: "checkmark.shield")
            LifecycleRow(label: "Crude / product", value: r.bestMatch)
            LifecycleRow(label: "Confidence",      value: "\(r.confidencePct)%")
            if let alts = r.alternates, !alts.isEmpty {
                LifecycleRow(label: "Alternates", value: alts.joined(separator: ", "))
            }
        }
    }

    private var ctaRow: some View {
        Button { Task { await match() } } label: {
            HStack(spacing: 6) {
                if loading { ProgressView().tint(.white) }
                Text(loading ? "Matching…" : "Run match").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(loading || apiGravity == nil)
    }

    private func match() async {
        loading = true; actionError = nil
        struct In: Encodable { let api: Double; let sulfur: Double?; let pour: Double? }
        do {
            let r: SpectraResult = try await EusoTripAPI.shared.query("spectraMatch.identify", input: In(api: apiGravity ?? 0, sulfur: sulfur, pour: pourPoint))
            result = r
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("424 · SpectraMatch · Night") { SpectraMatchScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("424 · SpectraMatch · Afternoon") { SpectraMatchScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
