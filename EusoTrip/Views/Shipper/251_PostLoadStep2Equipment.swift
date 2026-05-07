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
                escortCard
                endorsementsCard
                specialEquipmentCard
                catalystGateCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
        }
    }

    // MARK: - Escort + endorsements + special-equipment + catalyst-gate
    //
    // Web parity from `LoadCreationWizard.tsx` step 4 — these were
    // missing from the iOS wizard and a shipper couldn't post an
    // oversize hazmat lane that needed escort + Hazmat-endorsed
    // driver + tarps + $5M insurance ceiling. Founder report
    // 2026-05-06: "no options for adding escort or escort
    // requirement. or equipment requirement thers a few key things
    // missing."

    private var escortCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ESCORT", icon: "shield.lefthalf.filled")
            Toggle("Requires escort", isOn: $draft.requiresEscort)
                .toggleStyle(SwitchToggleStyle(tint: Brand.warning))
            if draft.requiresEscort {
                HStack {
                    Text("Escort headcount").font(EType.caption).foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Picker("", selection: Binding(
                        get: { draft.escortCount ?? 1 },
                        set: { draft.escortCount = $0 }
                    )) {
                        Text("1 (lead)").tag(1)
                        Text("2 (lead + chase)").tag(2)
                        Text("3").tag(3)
                        Text("4").tag(4)
                    }
                    .pickerStyle(.menu).labelsHidden()
                }
            }
        }
    }

    private var endorsementsCard: some View {
        // Multi-select chips. Tap to toggle; selected chips fill with
        // the brand gradient. Server accepts the canonical IDs in
        // `requiredEndorsements: string[]`.
        let options: [(id: String, label: String)] = [
            ("TWIC",            "TWIC"),
            ("Hazmat",          "Hazmat (H)"),
            ("Tanker",          "Tanker (N)"),
            ("DoublesTriples",  "Doubles/Triples (T)"),
            ("Passenger",       "Passenger (P)"),
        ]
        return LifecycleCard {
            LifecycleSection(label: "REQUIRED ENDORSEMENTS", icon: "checkmark.seal")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.id) { opt in
                        let active = draft.requiredEndorsements.contains(opt.id)
                        Button {
                            toggle(&draft.requiredEndorsements, opt.id)
                        } label: {
                            Text(opt.label)
                                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(active ? .white : palette.textPrimary)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(active
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.tintNeutral))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var specialEquipmentCard: some View {
        // Same chip pattern as endorsements. Canonical equipment IDs
        // match the web platform's `specialEquipment` enum values.
        let options: [(id: String, label: String)] = [
            ("tarps",           "Tarps"),
            ("chains",          "Chains"),
            ("straps",          "Straps"),
            ("edge_protectors", "Edge Protectors"),
            ("load_locks",      "Load Locks"),
            ("liftgate",        "Liftgate"),
            ("ramps",           "Ramps"),
            ("pallet_jack",     "Pallet Jack"),
        ]
        return LifecycleCard {
            LifecycleSection(label: "SPECIAL EQUIPMENT", icon: "wrench.and.screwdriver")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.id) { opt in
                        let active = draft.specialEquipment.contains(opt.id)
                        Button {
                            toggle(&draft.specialEquipment, opt.id)
                        } label: {
                            Text(opt.label)
                                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(active ? .white : palette.textPrimary)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(active
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.tintNeutral))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var catalystGateCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CATALYST REQUIREMENTS", icon: "person.badge.shield.checkmark")

            HStack {
                Text("Min insurance (USD)").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                TextField("1,000,000", text: $draft.minInsuranceCoverage)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            HStack {
                Text("Min FMCSA rating").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                Picker("", selection: $draft.minSafetyRating) {
                    Text("Satisfactory").tag("satisfactory")
                    Text("Conditional").tag("conditional")
                    Text("Unrated OK").tag("unrated")
                    Text("Any").tag("any")
                }
                .pickerStyle(.menu).labelsHidden()
            }
            Toggle("Hazmat operating authority required",
                   isOn: $draft.hazmatAuthRequired)
                .toggleStyle(SwitchToggleStyle(tint: Brand.warning))
            Toggle("Contract carriers only",
                   isOn: $draft.contractOnly)
                .toggleStyle(SwitchToggleStyle(tint: Brand.blue))
            Toggle("Escrow required (EusoWallet)",
                   isOn: $draft.escrowRequired)
                .toggleStyle(SwitchToggleStyle(tint: Brand.blue))
            Toggle("Appointment required (EusoTicket)",
                   isOn: $draft.appointmentRequired)
                .toggleStyle(SwitchToggleStyle(tint: Brand.blue))
        }
    }

    /// In-place toggle helper for the multi-select chip cards.
    private func toggle(_ list: inout [String], _ id: String) {
        if let i = list.firstIndex(of: id) { list.remove(at: i) }
        else                                { list.append(id) }
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
