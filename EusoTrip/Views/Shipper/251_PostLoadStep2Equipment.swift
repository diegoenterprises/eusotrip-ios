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

    // ── T-005 (canonical lock-in, 2026-05-20) ───────────────────────
    // Truck mode now reads from the canonical `TrailerCode` enum
    // (23 codes, vertical-filtered). Rail + vessel modes keep their
    // legacy display strings until T-034 lands the RailCarKind +
    // VesselClassKind UI. A typo in a TrailerCode rawValue is now a
    // compile error — drift impossible at the type system layer.

    /// Returns the canonical TrailerCode list for truck mode (vertical-filtered if a
    /// vertical is selected, else all 23). Tap writes `draft.trailer` (TrailerCode)
    /// AND mirrors to `draft.equipmentType` (String) for legacy consumers.
    private var truckTrailerChoices: [TrailerCode] {
        if let v = draft.vertical {
            return TrailerCode.filtered(by: v)
        }
        return TrailerCode.allCases
    }

    /// Legacy display strings retained for rail / vessel modes only. T-034
    /// will replace these with canonical RailCarKind / VesselClassKind chips.
    private var legacyDisplayChoices: [String] {
        switch draft.mode {
        case .truck:
            return []   // truck routes through truckTrailerChoices
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
                verticalCard         // T-006 · 2026-05-20
                cargoCard
                equipmentCard
                // T-034 · 2026-05-20 — Cross-track identifier card.
                // Renders only when mode is rail or vessel. Provides the
                // canonical equipment IDs (reporting marks + AAR class
                // for rail; BIC + ISO + IMO + MMSI for vessel) so the
                // catalyst's dispatcher receives a fully-identified
                // unit at dispatch time. Truck loads skip this entirely.
                if draft.mode == .rail || draft.mode == .vessel {
                    crossTrackIdentifiersCard
                }
                weightCard
                // T-007 · 2026-05-20: hazmat / reefer subforms now trigger
                // on the trailer's intrinsic property (TrailerCode.isHazmatEligible
                // / requiresReeferSubform) OR the cargoType, OR the vertical's
                // compliance overlay. The old cargoType-only gate missed cases
                // where a hazmat-eligible tanker was picked but cargoType
                // stayed .general (founder report).
                if isHazmatContext { hazmatLink }
                if isReeferContext { reeferLink }
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

    /// T-007 trigger logic — kept inline so the body composition reads
    /// cleanly. Returns true when the hazmat subform must be reachable.
    private var isHazmatContext: Bool {
        if draft.cargoType == .hazmat { return true }
        if draft.trailer?.isHazmatEligible == true { return true }
        if draft.vertical == .hazmat { return true }
        if draft.vertical == .tankerLiquidBulk { return true }
        return false
    }

    /// Reefer subform reachability — set whenever the trailer or cargo
    /// or vertical implies cold-chain handling.
    private var isReeferContext: Bool {
        if draft.cargoType == .refrigerated { return true }
        if draft.trailer?.requiresReeferSubform == true { return true }
        if draft.vertical == .refrigerated { return true }
        return false
    }

    // ── Vertical chip row (T-006 · 2026-05-20) ──────────────────────
    // Renders the canonical 12 industry verticals as horizontally-
    // scrollable chips. Tap toggles `draft.vertical`. Selected vertical
    // narrows the truck trailer list below via TrailerCode.filtered(by:).
    // Vertical also feeds `DocumentRequirements.forShipment(vertical:)`
    // on Step 4 and `FeeMultiplierEngine.compute(vertical:)` on Step 3.
    private var verticalCard: some View {
        LifecycleCard {
            LifecycleSection(label: "INDUSTRY VERTICAL", icon: "tag.square")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Vertical.allCases) { v in
                        let active = draft.vertical == v
                        Button {
                            // Tapping the active chip clears the vertical,
                            // tapping a new one selects it.
                            draft.vertical = active ? nil : v
                            // Clear trailer if it no longer fits the new vertical.
                            if let t = draft.trailer, !TrailerCode.filtered(by: v).contains(t) {
                                draft.trailer = nil
                                draft.equipmentType = ""
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: v.systemImage)
                                    .font(.system(size: 10, weight: .heavy))
                                Text(v.displayName)
                                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            }
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

    // T-034 (2026-05-20) — Cross-track identifier card. Mode-aware:
    // rail surfaces reporting marks + AAR car class; vessel surfaces
    // BIC + ISO 6346 + IMO + MMSI. Fields are optional — the wizard
    // doesn't gate Continue on them (they're nice-to-have metadata
    // the catalyst can confirm at dispatch) but they ride through to
    // the load row via `composedNotes()` so the catalyst's
    // dispatcher sees the canonical unit IDs.
    private var crossTrackIdentifiersCard: some View {
        LifecycleCard {
            if draft.mode == .rail {
                LifecycleSection(label: "RAIL IDENTIFIERS", icon: "tram.fill")
                identifierField(
                    label: "Reporting marks",
                    placeholder: "e.g., BNSF · UP · CSXT · NS",
                    text: $draft.reportingMarks
                )
                identifierField(
                    label: "AAR car class",
                    placeholder: "e.g., C113 covered hopper · T108 tank",
                    text: $draft.aarClass
                )
                Text("AAR reporting marks + car class let the catalyst's dispatcher confirm the exact car the load rides on. Optional but recommended for interchange-billing accuracy.")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if draft.mode == .vessel {
                LifecycleSection(label: "VESSEL IDENTIFIERS", icon: "ferry.fill")
                identifierField(
                    label: "BIC code",
                    placeholder: "e.g., MSCU1234567 (11-char container ID)",
                    text: $draft.bicCode
                )
                identifierField(
                    label: "ISO 6346 size/type",
                    placeholder: "e.g., 45G1 · 22T1",
                    text: $draft.isoCode
                )
                identifierField(
                    label: "IMO number",
                    placeholder: "e.g., 9123456 (7-digit vessel ID)",
                    text: $draft.imoNumber
                )
                identifierField(
                    label: "MMSI",
                    placeholder: "e.g., 367123456 (9-digit MMSI)",
                    text: $draft.mmsi
                )
                Text("BIC + ISO identify the container; IMO + MMSI identify the carrying vessel. All four ride to the load row so customs filings (US ACE / CBSA CARM / SAT Carta Porte) auto-populate.")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func identifierField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.characters)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var equipmentCard: some View {
        LifecycleCard {
            LifecycleSection(label: "EQUIPMENT", icon: "truck.box")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // T-005 (2026-05-20): truck mode now renders the canonical
                    // TrailerCode enum (23 codes, vertical-filtered). Selecting
                    // writes draft.trailer (TrailerCode) AND mirrors to
                    // draft.equipmentType for legacy back-compat. Rail / vessel
                    // modes fall through to the legacy display-string path until
                    // T-034 lands RailCarKind + VesselClassKind chips.
                    if draft.mode == .truck {
                        ForEach(truckTrailerChoices) { t in
                            let active = draft.trailer == t
                            Button {
                                draft.trailer = t
                                draft.equipmentType = t.rawValue   // legacy mirror
                                // Auto-snap vertical from the trailer's default
                                // when the user hasn't picked one yet — friendlier
                                // UX than forcing them to set vertical first.
                                if draft.vertical == nil {
                                    draft.vertical = t.defaultVertical
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.displayName)
                                        .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                    if t.isHazmatEligible {
                                        Text("HAZMAT-ELIGIBLE")
                                            .font(.system(size: 7, weight: .heavy)).tracking(0.6)
                                            .opacity(0.7)
                                    }
                                }
                                .foregroundStyle(active ? .white : palette.textPrimary)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(active
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.tintNeutral))
                                .clipShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    } else {
                        ForEach(legacyDisplayChoices, id: \.self) { c in
                            Button {
                                draft.equipmentType = c
                                draft.trailer = nil   // legacy path, canonical type cleared
                            } label: {
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
            // Selected-trailer summary chip (truck mode only — surfaces the
            // canonical spec line so the user sees "MC-306 / DOT-406 / DOT-407"
            // confirmation instead of just the display name pill above).
            if draft.mode == .truck, let t = draft.trailer {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(t.shortSpec)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(palette.bgCard.opacity(0.6))
                .clipShape(Capsule())
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
