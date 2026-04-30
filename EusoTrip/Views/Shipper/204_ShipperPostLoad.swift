//
//  204_ShipperPostLoad.swift
//  EusoTrip — Shipper · Post a Load (brick 204).
//
//  Parity-reconciled to `02 Shipper/Code/204_ShipperPostLoad.swift` per
//  _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: 4-step stepper (LANE → EQUIPMENT → PRICING → REVIEW),
//  TopBar (eyebrow + step counter + back chevron + Post a load title
//  + close X), IridescentHairline, lane card with bullet-circle
//  endpoints + dashed connector + swap button, route-meta pill,
//  schedule tile pair, equipment preview (locked behind step 2 with
//  hazmat diamond glyph), target rate estimate card, Continue/Submit
//  CTA per-step.
//
//  Real data preserved: ShipperPostLoadStore + shippers.create
//  mutation pipeline (validation, optional fields → nil coalesce,
//  reset form on success). Form bindings unchanged. Cargo type
//  picker kept on the EQUIPMENT step. Weight/rate/notes on the
//  PRICING step.
//
//  Persona canon (§11): Diego Usoro · Eusorone Technologies (companyId 1).
//  §11.2 anchor MATRIX-50 row this brick is calibrated against:
//    LD-260427-A38FB12C7E · Houston TX → Dallas TX · MC-306 · UN1203 ·
//    50,000 lb · target $1,950 (= $8.16/mi, +3% above $7.92/mi spot).
//
//  BottomNav: Home / Create Load (current) / Loads / Me — out of scope
//  per parity mandate §1.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - 4-step state machine

private enum PostLoadStep: Int, CaseIterable, Identifiable {
    case lane      = 1
    case equipment = 2
    case pricing   = 3
    case review    = 4

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .lane:      return "LANE"
        case .equipment: return "EQUIPMENT"
        case .pricing:   return "PRICING"
        case .review:    return "REVIEW"
        }
    }
    var next: PostLoadStep? { PostLoadStep(rawValue: rawValue + 1) }
    var prev: PostLoadStep? { PostLoadStep(rawValue: rawValue - 1) }
}

// MARK: - Screen root

struct ShipperPostLoad: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var store = ShipperPostLoadStore()

    // Wizard state
    @State private var step: PostLoadStep = .lane

    // Form state — preserved from prior surface
    @State private var origin: String = ""
    @State private var destination: String = ""
    @State private var cargoType: ShipperAPI.CargoType = .general
    @State private var hasPickupDate: Bool = false
    @State private var pickupDate: Date = Date()
    @State private var weightText: String = ""
    @State private var rateText: String = ""
    @State private var notes: String = ""

    @State private var lastSuccess: ShipperAPI.PostLoadAck? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
                .padding(.horizontal, Space.s5)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    stepper
                    if let ack = lastSuccess {
                        successBanner(ack)
                    }
                    if case .error(let message) = store.phase {
                        errorBanner(message)
                    }
                    stepBody
                    continueOrSubmitCTA
                    Color.clear.frame(height: 96)
                }
                .padding(Space.s5)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .screenTileRoot()
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ SHIPPER · POST A LOAD · STEP \(step.rawValue) / \(PostLoadStep.allCases.count)")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(autosaveLine)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Button(action: backTapped) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text("Post a load")
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                Spacer()

                Button(action: closeTapped) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel and discard draft")
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var autosaveLine: String {
        switch store.phase {
        case .submitting: return "POSTING…"
        case .success:    return "POSTED"
        case .error:      return "DRAFT · ERROR"
        case .idle:       return "DRAFT · AUTOSAVED"
        }
    }

    private func backTapped() {
        if let p = step.prev {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) { step = p }
        } else {
            NotificationCenter.default.post(name: .eusoShipperPostLoadDismiss, object: nil)
        }
    }

    private func closeTapped() {
        NotificationCenter.default.post(name: .eusoShipperPostLoadDismiss, object: nil)
    }

    // MARK: - Stepper

    private var stepper: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(PostLoadStep.allCases) { s in
                    stepDot(for: s)
                    if s != PostLoadStep.allCases.last {
                        Rectangle()
                            .fill(s.rawValue < step.rawValue
                                  ? AnyShapeStyle(LinearGradient.primary)
                                  : AnyShapeStyle(palette.textTertiary.opacity(0.20)))
                            .frame(height: 2)
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(PostLoadStep.allCases) { s in
                    Text(s.label)
                        .font(EType.micro).tracking(0.5)
                        .foregroundStyle(s == step
                                         ? AnyShapeStyle(palette.textPrimary)
                                         : AnyShapeStyle(palette.textTertiary))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, Space.s2)
    }

    private func stepDot(for s: PostLoadStep) -> some View {
        let isActive = (s == step)
        let isComplete = (s.rawValue < step.rawValue)
        return ZStack {
            Circle()
                .fill((isActive || isComplete)
                      ? AnyShapeStyle(LinearGradient.primary)
                      : AnyShapeStyle(palette.bgCard))
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .frame(width: 28, height: 28)
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
            } else {
                Text("\(s.rawValue)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(isActive ? .white : palette.textTertiary)
            }
        }
        .accessibilityLabel("Step \(s.rawValue) of \(PostLoadStep.allCases.count)" +
                            (isActive ? ", current" : isComplete ? ", complete" : ""))
    }

    // MARK: - Step body switch

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .lane:      laneStepBody
        case .equipment: equipmentStepBody
        case .pricing:   pricingStepBody
        case .review:    reviewStepBody
        }
    }

    // MARK: - Step 1: LANE

    @ViewBuilder
    private var laneStepBody: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            laneSection
            routeMetaPill
            scheduleSection
        }
    }

    private var laneSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LANE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    laneField(label: "ORIGIN",
                              binding: $origin,
                              placeholder: "City, ST · e.g. Houston, TX")
                    laneConnector
                    laneField(label: "DESTINATION",
                              binding: $destination,
                              placeholder: "City, ST · e.g. Dallas, TX")
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

                Button(action: swapEndpoints) {
                    swapButton
                }
                .buttonStyle(.plain)
                .padding(Space.s4)
                .accessibilityLabel("Swap origin and destination")
            }
        }
    }

    private func laneField(label: String, binding: Binding<String>, placeholder: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .stroke(LinearGradient.primary, lineWidth: 2)
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(LinearGradient.primary)
                    .frame(width: 5, height: 5)
            }
            .padding(.top, 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                TextField(placeholder, text: binding)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .disabled(isSubmitting)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var laneConnector: some View {
        Rectangle()
            .fill(LinearGradient.primary)
            .frame(width: 2, height: 24)
            .mask(
                VStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { _ in
                        Rectangle().frame(width: 2, height: 2)
                    }
                }
            )
            .padding(.leading, 6)
            .padding(.vertical, 4)
    }

    private var swapButton: some View {
        ZStack {
            Circle().fill(palette.bgCard).frame(width: 32, height: 32)
            Circle().strokeBorder(palette.borderFaint).frame(width: 32, height: 32)
            VStack(spacing: 2) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .heavy))
                Image(systemName: "arrow.left")
                    .font(.system(size: 9, weight: .heavy))
            }
            .foregroundStyle(palette.textPrimary)
        }
    }

    private func swapEndpoints() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            let tmp = origin
            origin = destination
            destination = tmp
        }
    }

    private var routeMetaPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.swap")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.primary)
            Text(routeMetaText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 10)
        .background(LinearGradient(colors: [Brand.blue.opacity(0.06),
                                            Brand.magenta.opacity(0.06)],
                                   startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var routeMetaText: String {
        let oTrim = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let dTrim = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if oTrim.isEmpty || dTrim.isEmpty {
            return "Add origin + destination — distance / ETA estimates auto-fill"
        }
        return "Estimating distance · ETA · best-route via HERE Routing v8"
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SCHEDULE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                pickupTile
                deliveryTile
            }
        }
    }

    private var pickupTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PICKUP")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Toggle("Schedule", isOn: $hasPickupDate.animation(.spring(response: 0.22, dampingFraction: 0.85)))
                    .toggleStyle(GradientToggleStyle())
                    .labelsHidden()
            }
            if hasPickupDate {
                DatePicker("Pickup", selection: $pickupDate, in: Date()..., displayedComponents: [.date])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(LinearGradient.diagonal)
                    .disabled(isSubmitting)
            } else {
                Text("Catalyst proposes")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Leave blank or schedule")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var deliveryTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DELIVERY")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(hasPickupDate ? "ETA computed" : "Catalyst proposes")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Text(hasPickupDate ? "Auto-set from pickup + lane" : "Set after pickup is scheduled")
                .font(EType.caption).monospacedDigit()
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Step 2: EQUIPMENT

    @ViewBuilder
    private var equipmentStepBody: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            cargoTypePicker
            weightField
            equipmentPreviewSection
        }
    }

    private var cargoTypePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CARGO TYPE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ShipperAPI.CargoType.allCases) { type in
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                cargoType = type
                            }
                        } label: {
                            cargoChip(for: type)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func cargoChip(for type: ShipperAPI.CargoType) -> some View {
        let on = (cargoType == type)
        HStack(spacing: 6) {
            Image(systemName: type.systemImage)
                .font(.system(size: 10, weight: .heavy))
            Text(type.label)
                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
        }
        .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textSecondary))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard)))
        .overlay(Capsule().strokeBorder(on ? AnyShapeStyle(.clear) : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
    }

    private var weightField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WEIGHT")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 18)
                TextField("0", text: $weightText)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .keyboardType(.decimalPad)
                    .disabled(isSubmitting)
                Text("lbs")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private var equipmentPreviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EQUIPMENT · PREVIEW")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .top, spacing: Space.s3) {
                glyph(for: cargoType)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(cargoType.label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(equipmentSpecText)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Text(equipmentNoteText)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    @ViewBuilder
    private func glyph(for type: ShipperAPI.CargoType) -> some View {
        let lower = type.label.lowercased()
        if type.label.lowercased() == "hazmat" || lower.contains("petroleum") || lower.contains("chemicals") || lower.contains("liquid") || lower.contains("gas") || lower.contains("cryogenic") {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Brand.hazmat.opacity(0.16))
                Rectangle()
                    .stroke(Brand.hazmat, lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(45))
                Text("3")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color(hex: 0xB27300))
                    .offset(y: 4)
            }
        } else if lower.contains("refrigerated") || lower.contains("food") {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Brand.info.opacity(0.12))
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Brand.info, lineWidth: 2)
                    .frame(width: 30, height: 24)
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.bgCardSoft)
                Image(systemName: type.systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    /// Equipment spec hint per cargoType — calibrated against the §11.4
    /// MATRIX-50 anchor rows (UN1203 / MC-306, MC-331 NH₃, 53′ Reefer).
    /// Eusotrans LLC USDOT 3 194 882 runs MC-306 + MC-331 multi-equipment.
    private var equipmentSpecText: String {
        switch cargoType.label.lowercased() {
        case "hazmat", "petroleum":  return "MC-306 · UN1203 · PG II"
        case "chemicals":            return "MC-307 · UN1760 · PG II"
        case "liquid":               return "MC-307 · food-grade liner"
        case "gas":                  return "MC-331 · UN1075 · cryo"
        case "cryogenic":            return "MC-338 · LIN/LOX"
        case "refrigerated":         return "53′ Reefer · 33–40°F"
        case "food_grade", "food grade": return "Food-grade trailer · sanitary"
        case "dry_bulk", "dry bulk", "grain": return "Pneumatic / hopper · sealed"
        case "intermodal":           return "20′/40′/53′ ISO container"
        case "oversized", "vehicles","timber": return "Flatbed / step-deck"
        case "livestock":            return "Possum-belly · ventilated"
        default:                     return "53′ Dry Van · standard"
        }
    }

    private var equipmentNoteText: String {
        switch cargoType.label.lowercased() {
        case "hazmat", "petroleum", "chemicals", "gas", "cryogenic":
            return "CHEMTREC +1-800-424-9300 · escort optional"
        case "refrigerated", "food_grade", "food grade":
            return "Continuous temp logging · last-load-out check"
        case "intermodal":
            return "Chassis pool · per diem after free time"
        default:
            return "Standard tender · no special notes"
        }
    }

    // MARK: - Step 3: PRICING

    @ViewBuilder
    private var pricingStepBody: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            rateField
            targetRateCard
            notesField
        }
    }

    private var rateField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("POSTED RATE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 18)
                TextField("0", text: $rateText)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .keyboardType(.decimalPad)
                    .disabled(isSubmitting)
                Text("USD")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private var targetRateCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TARGET RATE · ESTIMATE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(targetRateText)
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("· spot avg estimate")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(targetTrailText)
                .font(EType.caption)
                .foregroundStyle(targetTrailColor)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var targetRateText: String {
        if let r = parseDouble(rateText), r > 0 { return dollars(r) }
        return "—"
    }

    private var targetTrailText: String {
        guard let r = parseDouble(rateText), r > 0 else {
            return "Add rate to see vs spot"
        }
        return "estimate vs spot"
    }
    private var targetTrailColor: Color { palette.textSecondary }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES (OPTIONAL)")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            TextField(
                "Anything carriers should know — temperature ranges, dock hours, COI…",
                text: $notes,
                axis: .vertical
            )
            .font(EType.body)
            .foregroundStyle(palette.textPrimary)
            .tint(LinearGradient.diagonal)
            .lineLimit(3...6)
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .disabled(isSubmitting)
        }
    }

    // MARK: - Step 4: REVIEW

    @ViewBuilder
    private var reviewStepBody: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            reviewSummaryCard
        }
    }

    private var reviewSummaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            reviewRow(label: "Origin",       value: nonEmpty(origin))
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Destination",  value: nonEmpty(destination))
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Cargo type",   value: cargoType.label)
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Pickup",       value: hasPickupDate ? formatDate(pickupDate) : "Catalyst proposes")
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Weight",       value: parseDouble(weightText).map { "\(Int($0)) lbs" } ?? "—")
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Posted rate",  value: parseDouble(rateText).map(dollars) ?? "—", isHero: true)
            if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Notes",    value: notes)
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }

    private func reviewRow(label: String, value: String, isHero: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(value)
                .font(isHero ? .system(size: 22, weight: .bold) : EType.bodyStrong)
                .foregroundStyle(isHero ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textPrimary))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private func nonEmpty(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "—" : t
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f.string(from: d)
    }

    // MARK: - Banners

    private func successBanner(_ ack: ShipperAPI.PostLoadAck) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text("Load posted")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(loadNumberSubtitle(ack))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button { withAnimation { lastSuccess = nil } } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func loadNumberSubtitle(_ ack: ShipperAPI.PostLoadAck) -> String {
        let trimmed = ack.loadNumber.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Bids will land in your Bids inbox." }
        return "\(trimmed) · bids will land in your Bids inbox."
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't post that load")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button { store.reset() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Continue / Submit CTA

    private var continueOrSubmitCTA: some View {
        Button(action: continueOrSubmit) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else if step == .review {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                }
                Text(ctaText)
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                Capsule().fill(canAdvance
                               ? AnyShapeStyle(LinearGradient.primary)
                               : AnyShapeStyle(palette.tintNeutral.opacity(0.4)))
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canAdvance)
        .accessibilityLabel(ctaText)
    }

    private var ctaText: String {
        if case .success = store.phase, step == .review { return "Post another" }
        if step == .review {
            return isSubmitting ? "Posting…" : "Post this load"
        }
        guard let next = step.next else { return "Continue" }
        return "Continue · Step \(next.rawValue) of \(PostLoadStep.allCases.count) →"
    }

    private var canAdvance: Bool {
        if isSubmitting { return false }
        switch step {
        case .lane:
            let oTrim = origin.trimmingCharacters(in: .whitespacesAndNewlines)
            let dTrim = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            return !oTrim.isEmpty && !dTrim.isEmpty
        case .equipment, .pricing, .review:
            return true
        }
    }

    private func continueOrSubmit() {
        if step == .review {
            if case .success = store.phase {
                resetForm()
                store.reset()
                step = .lane
                return
            }
            Task { await submit() }
        } else if let next = step.next {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                step = next
            }
        }
    }

    // MARK: - Submit pipeline (preserved verbatim)

    private var isSubmitting: Bool {
        if case .submitting = store.phase { return true }
        return false
    }

    private func submit() async {
        let pickupISO = hasPickupDate ? isoDate(pickupDate) : nil
        let weight    = parseDouble(weightText)
        let rate      = parseDouble(rateText)
        await store.submit(
            origin: origin,
            destination: destination,
            cargoType: cargoType,
            rate: rate,
            weight: weight,
            notes: notes,
            pickupDate: pickupISO
        )
        if case .success(let ack) = store.phase {
            self.lastSuccess = ack
            resetForm()
        }
    }

    private func resetForm() {
        origin = ""
        destination = ""
        hasPickupDate = false
        pickupDate = Date()
        weightText = ""
        rateText = ""
        notes = ""
    }

    private func parseDouble(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let cleaned = trimmed.replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }

    private func dollars(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let eusoShipperPostLoadDismiss = Notification.Name("eusoShipperPostLoadDismiss")
}

// MARK: - Screen wrapper

struct ShipperPostLoadScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperPostLoad()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_204(),
                trailing: shipperNavTrailing_204(),
                orbState: .idle
            )
        }
    }
}

// Shipper bottom-nav doctrine — out of scope per parity mandate §1.
private func shipperNavLeading_204() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                              isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle.fill",   isCurrent: true)]
}

private func shipperNavTrailing_204() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

// MARK: - Previews

#Preview("204 · Shipper · Post Load · Night") {
    ShipperPostLoadScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("204 · Shipper · Post Load · Afternoon") {
    ShipperPostLoadScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
