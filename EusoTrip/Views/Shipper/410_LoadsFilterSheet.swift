//
//  410_LoadsFilterSheet.swift
//  EusoTrip — Shipper · Loads filter sheet (Arc C deepening).
//

import SwiftUI

struct LoadsFilterSheetScreen: View {
    let theme: Theme.Palette
    @Binding var selectedStatus: String?
    @Binding var selectedEquipment: String?
    @Binding var selectedCargo: String?
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    @Binding var rateMin: Double?
    @Binding var rateMax: Double?
    var onApply: () -> Void
    var onClear: () -> Void
    var body: some View {
        Shell(theme: theme) { FilterSheetBody(selectedStatus: $selectedStatus, selectedEquipment: $selectedEquipment, selectedCargo: $selectedCargo, dateFrom: $dateFrom, dateTo: $dateTo, rateMin: $rateMin, rateMax: $rateMax, onApply: onApply, onClear: onClear) } nav: { shipperLifecycleNav() }
    }
}

private struct FilterSheetBody: View {
    @Environment(\.palette) private var palette
    @Binding var selectedStatus: String?
    @Binding var selectedEquipment: String?
    @Binding var selectedCargo: String?
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    @Binding var rateMin: Double?
    @Binding var rateMax: Double?
    let onApply: () -> Void
    let onClear: () -> Void

    private let statuses = ["posted", "bidding", "assigned", "in_transit", "delivered", "cancelled"]
    private let equipment = ["53' Dry Van", "53' Reefer", "Flatbed 48'", "MC-306 Tanker", "MC-331 Tanker", "Container 40' HC"]
    private let cargoTypes = ["general", "hazmat", "refrigerated", "oversized", "petroleum", "chemicals"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                statusCard
                equipmentCard
                cargoCard
                dateCard
                rateCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · LOADS · FILTER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Filter loads").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var statusCard: some View {
        LifecycleCard {
            LifecycleSection(label: "STATUS", icon: "flag")
            chips(items: statuses, selected: selectedStatus) { selectedStatus = selectedStatus == $0 ? nil : $0 }
        }
    }

    private var equipmentCard: some View {
        LifecycleCard {
            LifecycleSection(label: "EQUIPMENT", icon: "truck.box")
            chips(items: equipment, selected: selectedEquipment) { selectedEquipment = selectedEquipment == $0 ? nil : $0 }
        }
    }

    private var cargoCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CARGO TYPE", icon: "tag")
            chips(items: cargoTypes, selected: selectedCargo) { selectedCargo = selectedCargo == $0 ? nil : $0 }
        }
    }

    private var dateCard: some View {
        LifecycleCard {
            LifecycleSection(label: "PICKUP DATE RANGE", icon: "calendar")
            HStack {
                DatePicker("From", selection: Binding(get: { dateFrom ?? Date() }, set: { dateFrom = $0 }), displayedComponents: .date).labelsHidden()
                Text("→").foregroundStyle(palette.textTertiary)
                DatePicker("To", selection: Binding(get: { dateTo ?? Date().addingTimeInterval(7*86400) }, set: { dateTo = $0 }), displayedComponents: .date).labelsHidden()
            }
        }
    }

    private var rateCard: some View {
        LifecycleCard {
            LifecycleSection(label: "RATE RANGE (USD)", icon: "dollarsign.circle")
            HStack {
                TextField("Min", value: $rateMin, format: .number).keyboardType(.numberPad).textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("→").foregroundStyle(palette.textTertiary)
                TextField("Max", value: $rateMax, format: .number).keyboardType(.numberPad).textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func chips(items: [String], selected: String?, onTap: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Button { onTap(item) } label: {
                        Text(item.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(selected == item ? .white : palette.textPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(selected == item ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button(action: onClear) {
                Text("Clear").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(palette.tintNeutral).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Button(action: onApply) {
                Text("Apply").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }
}

#Preview("410 · Filter · Night") {
    LoadsFilterSheetScreen(theme: Theme.dark, selectedStatus: .constant(nil), selectedEquipment: .constant(nil), selectedCargo: .constant(nil), dateFrom: .constant(nil), dateTo: .constant(nil), rateMin: .constant(nil), rateMax: .constant(nil), onApply: {}, onClear: {})
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("410 · Filter · Afternoon") {
    LoadsFilterSheetScreen(theme: Theme.light, selectedStatus: .constant(nil), selectedEquipment: .constant(nil), selectedCargo: .constant(nil), dateFrom: .constant(nil), dateTo: .constant(nil), rateMin: .constant(nil), rateMax: .constant(nil), onApply: {}, onClear: {})
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
