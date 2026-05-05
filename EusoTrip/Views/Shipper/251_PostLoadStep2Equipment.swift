//
//  251_PostLoadStep2Equipment.swift
//  EusoTrip — Shipper · Post-a-Load · Step 2 EQUIPMENT.
//

import SwiftUI

struct PostLoadStep2EquipmentScreen: View {
    let theme: Theme.Palette
    @ObservedObject var draft: PostLoadDraft

    var body: some View {
        Shell(theme: theme) {
            PostLoadStep2Body(draft: draft)
        } nav: { shipperLifecycleNav() }
    }
}

private struct PostLoadStep2Body: View {
    @Environment(\.palette) private var palette
    @ObservedObject var draft: PostLoadDraft

    private var equipmentChoices: [String] {
        switch draft.mode {
        case .truck:
            return [
                "53' Dry Van", "53' Reefer", "Flatbed 48'", "Step Deck", "Conestoga",
                "MC-306 Tanker", "MC-307 Tanker", "MC-331 Tanker", "Container 40' HC",
                "Power Only", "Lowboy", "Hot Shot",
            ]
        case .rail:
            return [
                "Boxcar", "Hopper", "Tank Car (UTLX)", "Centerbeam", "Gondola",
                "Well Car (Intermodal)", "Auto Rack", "Refrigerated Boxcar",
                "Pressure Tank Car (DOT-105)", "Flat Car",
            ]
        case .vessel:
            return [
                "20' Container", "40' Container", "40' HC", "45' HC",
                "Reefer Container", "ISO Tank", "Bulk Carrier",
                "Tanker (Crude)", "Tanker (Product)", "RoRo", "LNG Carrier",
            ]
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                cargoCard
                equipmentCard
                weightCard
                if draft.cargoType == .hazmat { hazmatLink }
                if draft.cargoType == .refrigerated { reeferLink }
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("POST A LOAD · STEP 2 · EQUIPMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text("What's the equipment?")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.75)
        }
    }

    private var cargoCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CARGO TYPE", icon: "tag")
            Picker("", selection: $draft.cargoType) {
                ForEach(PostLoadDraft.CargoType.allCases) { ct in
                    Text(ct.label).tag(ct)
                }
            }.pickerStyle(.menu).labelsHidden()
        }
    }

    private var equipmentCard: some View {
        LifecycleCard {
            LifecycleSection(label: "EQUIPMENT", icon: "truck.box")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(equipmentChoices, id: \.self) { c in
                        Button { draft.equipmentType = c } label: {
                            Text(c).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(draft.equipmentType == c ? .white : palette.textPrimary)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(draft.equipmentType == c
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.tintNeutral))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var weightCard: some View {
        LifecycleCard {
            LifecycleSection(label: "WEIGHT (LB)", icon: "scalemass")
            TextField("e.g. 42000", value: $draft.weight, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var hazmatLink: some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "257"])
        } label: {
            HStack {
                Image(systemName: "triangle.fill").foregroundStyle(Brand.warning)
                Text("Configure hazmat fields").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.warning.opacity(0.5), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }

    private var reeferLink: some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "258"])
        } label: {
            HStack {
                Image(systemName: "thermometer").foregroundStyle(LinearGradient.diagonal)
                Text("Configure reefer setpoint").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "250"])
            } label: {
                Text("Back").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(palette.tintNeutral).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "252"])
            } label: {
                Text("Continue").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }
}

#Preview("251 · Equipment · Night") {
    PostLoadStep2EquipmentScreen(theme: Theme.dark, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("251 · Equipment · Afternoon") {
    PostLoadStep2EquipmentScreen(theme: Theme.light, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
