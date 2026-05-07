//
//  342_LaneTemplateEditor.swift
//  EusoTrip — Shipper · Lane template editor (Arc K).
//

import SwiftUI

struct LaneTemplateEditorScreen: View {
    let theme: Theme.Palette
    let templateId: String
    var body: some View {
        Shell(theme: theme) { LaneTemplateEditorBody(templateId: templateId) } nav: { shipperLifecycleNav() }
    }
}

private struct LaneTemplateEditorBody: View {
    @Environment(\.palette) private var palette
    let templateId: String
    @State private var name: String = ""
    @State private var origin: String = ""
    @State private var destination: String = ""
    @State private var cargoType: String = "general"
    @State private var equipmentType: String = ""
    @State private var rate: Double? = nil
    @State private var weight: Double? = nil
    @State private var sending: Bool = false
    @State private var saved: Bool = false
    @State private var actionError: String? = nil
    @State private var loading: Bool = false

    private let cargoTypes = ["general", "hazmat", "refrigerated", "oversized", "liquid", "gas", "chemicals", "petroleum"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if saved { LifecycleCard(accentGradient: true) { Text("Template saved.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                fieldsCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await loadIfExisting() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "pencil").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · LANE TEMPLATE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(templateId == "new" ? "New template" : "Edit template").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var fieldsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "TEMPLATE", icon: "doc.text")
            field("Name", text: $name)
            field("Origin", text: $origin)
            field("Destination", text: $destination)
            VStack(alignment: .leading, spacing: 4) {
                Text("CARGO TYPE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Picker("", selection: $cargoType) { ForEach(cargoTypes, id: \.self) { Text($0.capitalized).tag($0) } }.pickerStyle(.menu).labelsHidden()
            }
            field("Equipment", text: $equipmentType)
            VStack(alignment: .leading, spacing: 4) {
                Text("RATE (USD)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                TextField("", value: $rate, format: .number).keyboardType(.decimalPad).textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("WEIGHT (LB)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                TextField("", value: $weight, format: .number).keyboardType(.numberPad).textFieldStyle(.plain)
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
            TextField(label, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var ctaRow: some View {
        Button { Task { await save() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Saving…" : "Save template").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending || name.isEmpty)
    }

    private func loadIfExisting() async {
        guard templateId != "new" else { return }
        loading = true
        struct In: Encodable { let id: String }
        struct Out: Decodable {
            let name: String; let origin: String?; let destination: String?
            let cargoType: String?; let equipmentType: String?; let rate: Double?; let weight: Double?
        }
        do {
            let t: Out = try await EusoTripAPI.shared.query("loadTemplates.getById", input: In(id: templateId))
            name = t.name; origin = t.origin ?? ""; destination = t.destination ?? ""
            cargoType = t.cargoType ?? "general"; equipmentType = t.equipmentType ?? ""
            rate = t.rate; weight = t.weight
        } catch { /* tolerate */ }
        loading = false
    }

    private func save() async {
        sending = true; actionError = nil
        struct In: Encodable {
            let id: String?; let name: String; let origin: String; let destination: String
            let cargoType: String; let equipmentType: String?; let rate: Double?; let weight: Double?
        }
        struct Out: Decodable { let success: Bool; let templateId: String? }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation(
                templateId == "new" ? "loadTemplates.create" : "loadTemplates.update",
                input: In(id: templateId == "new" ? nil : templateId, name: name, origin: origin, destination: destination, cargoType: cargoType, equipmentType: equipmentType.isEmpty ? nil : equipmentType, rate: rate, weight: weight)
            )
            saved = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("342 · Template editor · Night") { LaneTemplateEditorScreen(theme: Theme.dark, templateId: "new").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("342 · Template editor · Afternoon") { LaneTemplateEditorScreen(theme: Theme.light, templateId: "new").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
