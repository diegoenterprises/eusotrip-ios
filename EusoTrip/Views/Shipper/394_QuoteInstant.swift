//
//  394_QuoteInstant.swift
//  EusoTrip — Shipper · Instant quote (Arc B+).
//

import SwiftUI

struct QuoteInstantScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { QuoteBody() } nav: { shipperLifecycleNav() }
    }
}

private struct QuoteResult: Decodable, Hashable {
    let lowUsd: Double?
    let midUsd: Double?
    let highUsd: Double?
    let confidencePct: Int?
    let comparable: Int?
    let lane: String?
}

private struct QuoteBody: View {
    @Environment(\.palette) private var palette
    @State private var origin: String = ""
    @State private var destination: String = ""
    @State private var equipmentType: String = "53' Dry Van"
    @State private var weight: Double? = nil
    @State private var loading = false
    @State private var result: QuoteResult? = nil
    @State private var actionError: String? = nil

    private let equipmentChoices = ["53' Dry Van", "53' Reefer", "Flatbed 48'", "MC-306 Tanker", "MC-331 Tanker", "Container 40' HC", "Power Only"]

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
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · INSTANT QUOTE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Quote a lane").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Pulls comparable rates over the last 30 days for this lane + equipment.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inputCard: some View {
        LifecycleCard {
            LifecycleSection(label: "INPUTS", icon: "pencil")
            field("Origin", text: $origin)
            field("Destination", text: $destination)
            VStack(alignment: .leading, spacing: 4) {
                Text("EQUIPMENT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Picker("", selection: $equipmentType) { ForEach(equipmentChoices, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("WEIGHT (LB)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                TextField("e.g. 42000", value: $weight, format: .number).keyboardType(.numberPad).textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            TextField(label, text: text).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func resultCard(_ r: QuoteResult) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: dashIfEmpty(r.lane), icon: "chart.bar")
            HStack(spacing: Space.s2) {
                LifecycleStatTile(label: "LOW",    value: usd(r.lowUsd), icon: "arrow.down.circle")
                LifecycleStatTile(label: "MID",    value: usd(r.midUsd), icon: "scalemass")
                LifecycleStatTile(label: "HIGH",   value: usd(r.highUsd), icon: "arrow.up.circle")
            }
            LifecycleRow(label: "Confidence",  value: r.confidencePct.map { "\($0)%" } ?? "—")
            LifecycleRow(label: "Comparable",   value: r.comparable.map { "\($0) loads" } ?? "—")
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button { Task { await runQuote() } } label: {
                HStack(spacing: 6) {
                    if loading { ProgressView().tint(.white) }
                    Text(loading ? "Calculating…" : "Get quote").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(loading || origin.isEmpty || destination.isEmpty)
            if result != nil {
                Button { Task { await save() } } label: {
                    Image(systemName: "bookmark.fill").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        .frame(width: 44, height: 44).background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    private func runQuote() async {
        loading = true; actionError = nil
        struct In: Encodable { let origin: String; let destination: String; let equipmentType: String; let weight: Double? }
        do {
            let r: QuoteResult = try await EusoTripAPI.shared.api.query("predictivePricing.quote", input: In(origin: origin, destination: destination, equipmentType: equipmentType, weight: weight))
            result = r
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func save() async {
        struct In: Encodable { let origin: String; let destination: String; let equipmentType: String; let weight: Double? }
        struct Out: Decodable { let success: Bool }
        let _ : Out = (try? await EusoTripAPI.shared.api.mutation("predictivePricing.saveQuote", input: In(origin: origin, destination: destination, equipmentType: equipmentType, weight: weight))) ?? Out(success: false)
    }
}

#Preview("394 · Quote · Night") { QuoteInstantScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("394 · Quote · Afternoon") { QuoteInstantScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
