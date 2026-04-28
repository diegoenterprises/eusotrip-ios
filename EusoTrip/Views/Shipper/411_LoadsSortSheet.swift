//
//  411_LoadsSortSheet.swift
//  EusoTrip — Shipper · Loads sort sheet (Arc C deepening).
//

import SwiftUI

enum LoadsSortKey: String, CaseIterable, Identifiable {
    case newest, highestRate, bestMargin, soonestPickup, deliveryAsc, alpha
    var id: String { rawValue }
    var label: String {
        switch self {
        case .newest:        return "Newest first"
        case .highestRate:   return "Highest rate"
        case .bestMargin:    return "Best margin"
        case .soonestPickup: return "Soonest pickup"
        case .deliveryAsc:   return "Delivery date · ascending"
        case .alpha:         return "Load number · A→Z"
        }
    }
    var icon: String {
        switch self {
        case .newest:        return "calendar.badge.clock"
        case .highestRate:   return "arrow.up.circle"
        case .bestMargin:    return "chart.line.uptrend.xyaxis"
        case .soonestPickup: return "clock"
        case .deliveryAsc:   return "calendar"
        case .alpha:         return "textformat.abc"
        }
    }
}

struct LoadsSortSheetScreen: View {
    let theme: Theme.Palette
    @Binding var selected: LoadsSortKey
    var onApply: () -> Void
    var body: some View {
        Shell(theme: theme) { SortBody(selected: $selected, onApply: onApply) } nav: { shipperLifecycleNav() }
    }
}

private struct SortBody: View {
    @Environment(\.palette) private var palette
    @Binding var selected: LoadsSortKey
    let onApply: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                LifecycleCard {
                    LifecycleSection(label: "SORT BY", icon: "arrow.up.arrow.down")
                    ForEach(LoadsSortKey.allCases) { key in
                        Button { selected = key } label: {
                            HStack {
                                Image(systemName: key.icon).foregroundStyle(LinearGradient.diagonal)
                                Text(key.label).font(EType.body).foregroundStyle(palette.textPrimary)
                                Spacer(minLength: 0)
                                Image(systemName: selected == key ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected == key ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                            }
                            .padding(.vertical, 4)
                        }.buttonStyle(.plain)
                    }
                }
                Button(action: onApply) {
                    Text("Apply").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain)
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · LOADS · SORT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Sort loads").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }
}

#Preview("411 · Sort · Night") { LoadsSortSheetScreen(theme: Theme.dark, selected: .constant(.newest), onApply: {}).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("411 · Sort · Afternoon") { LoadsSortSheetScreen(theme: Theme.light, selected: .constant(.newest), onApply: {}).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
