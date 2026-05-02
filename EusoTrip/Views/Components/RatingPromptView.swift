//
//  RatingPromptView.swift
//  EusoTrip — Post-delivery counterparty rating prompt.
//
//  One sheet, both directions:
//    - Driver rates shipper after delivery (entityType="user", role="shipper")
//    - Shipper rates driver after settlement (entityType="user", role="driver")
//
//  Closes Phase 18 (Rating / review) of the 8000-scenario shipper↔driver
//  parity audit (docs/parity-2026/EXECUTIVE_VERDICT.md §4.5) — the
//  backend `ratings.submit` mutation has shipped since the 90th firing
//  but iOS had no prompt screen, so neither side could leave a rating.
//
//  Anchored by:
//    1. Counterparty header card — name + role + load summary
//    2. Five-tap big-tap stars — overall rating (required, 1-5)
//    3. Per-axis breakdown — communication / professionalism /
//       on-time / equipment / payment (driver-vs-shipper axis differs)
//    4. Optional comment (≤ 500 chars per server schema)
//    5. Anonymous toggle
//    6. Submit -> ratings.submit -> toast + dismiss
//
//  Production-grade per [feedback_swiftui_previews] + animation
//  doctrine §B.4. Dark + Light previews ship.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Direction

/// Which side is rating. Drives the axis labels (drivers care about
/// "payment promptness"; shippers care about "equipment condition")
/// and the header copy.
enum RatingDirection: String, Hashable {
    /// Driver is rating the shipper / consignee for the haul they
    /// just completed.
    case driverRatesShipper
    /// Shipper is rating the driver after settlement.
    case shipperRatesDriver

    var headlineEyebrow: String {
        switch self {
        case .driverRatesShipper: return "RATE THIS SHIPPER"
        case .shipperRatesDriver: return "RATE THIS DRIVER"
        }
    }

    var counterpartyRoleLabel: String {
        switch self {
        case .driverRatesShipper: return "shipper"
        case .shipperRatesDriver: return "driver"
        }
    }

    /// The axis labels the user picks per-axis scores on. Each side
    /// sees the axes that matter for their counterparty.
    var axisLabels: [(key: String, label: String, hint: String)] {
        switch self {
        case .driverRatesShipper:
            return [
                ("communication",       "Communication",       "Clear, prompt, accurate"),
                ("professionalism",     "Professionalism",     "Treated you like a partner"),
                ("delivery_quality",    "Dock readiness",      "Door open, paperwork ready"),
                ("payment_promptness",  "Payment promptness",  "Settlement cleared on time")
            ]
        case .shipperRatesDriver:
            return [
                ("communication",       "Communication",       "Updates, ETA accuracy, callbacks"),
                ("professionalism",     "Professionalism",     "Courteous to dock, in/out clean"),
                ("timeliness",          "On-time performance", "Pickup + delivery windows held"),
                ("equipment_condition", "Equipment condition", "Trailer clean, seals intact")
            ]
        }
    }
}

// MARK: - Sheet

struct RatingPromptView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    // MARK: Inputs

    let direction: RatingDirection
    /// User-id of the counterparty being rated.
    let counterpartyId: String
    /// Display name for the header card. Falls through to
    /// "this {role}" when nil.
    let counterpartyName: String?
    /// Backing load id (numeric string per server schema). Server
    /// enforces one-rating-per-load to prevent dup-spam.
    let loadId: String
    /// Optional lane summary ("Houston, TX → Dallas, TX") for the
    /// header card.
    let laneSummary: String?

    init(
        direction: RatingDirection,
        counterpartyId: String,
        counterpartyName: String? = nil,
        loadId: String,
        laneSummary: String? = nil
    ) {
        self.direction = direction
        self.counterpartyId = counterpartyId
        self.counterpartyName = counterpartyName
        self.loadId = loadId
        self.laneSummary = laneSummary
    }

    // MARK: Form state

    @State private var overall: Int = 0
    @State private var axisScores: [String: Int] = [:]
    @State private var comment: String = ""
    @State private var anonymous: Bool = false

    @State private var inFlight: Bool = false
    @State private var error: String? = nil
    @State private var success: Bool = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    headerCard
                    overallStarsCard
                    axisBreakdownCard
                    commentCard
                    if let err = error {
                        errorBanner(err)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { dismiss() }
                        .disabled(inFlight)
                }
                ToolbarItem(placement: .principal) {
                    Text(direction.headlineEyebrow)
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .safeAreaInset(edge: .bottom) {
                submitBar
                    .background(palette.bgPrimary)
            }
            .overlay(alignment: .bottom) {
                if success {
                    Text("Rating submitted · thank you")
                        .font(EType.caption).fontWeight(.semibold)
                        .foregroundStyle(palette.textOnGradient)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s2)
                        .background(Brand.success,
                                    in: RoundedRectangle(cornerRadius: Radius.md))
                        .padding(.bottom, 96)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Header card

    private var headerCard: some View {
        HStack(spacing: Space.s3) {
            // Gradient avatar with first letter of counterparty name.
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Text(initial)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(counterpartyName ?? "this \(direction.counterpartyRoleLabel)")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(direction.counterpartyRoleLabel.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                if let lane = laneSummary, !lane.isEmpty {
                    Text(lane)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var initial: String {
        if let n = counterpartyName, let first = n.first {
            return String(first).uppercased()
        }
        return direction == .driverRatesShipper ? "S" : "D"
    }

    // MARK: - Overall stars

    private var overallStarsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("OVERALL")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) {
                            overall = i
                        }
                    } label: {
                        Image(systemName: i <= overall ? "star.fill" : "star")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(
                                i <= overall
                                ? AnyShapeStyle(LinearGradient.diagonal)
                                : AnyShapeStyle(palette.textTertiary)
                            )
                            .scaleEffect(i == overall ? 1.1 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Text(overallLabel)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var overallLabel: String {
        switch overall {
        case 0: return "Tap to rate"
        case 1: return "Poor"
        case 2: return "Below average"
        case 3: return "Average"
        case 4: return "Good"
        case 5: return "Excellent"
        default: return ""
        }
    }

    // MARK: - Per-axis breakdown

    private var axisBreakdownCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("BREAKDOWN")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            ForEach(direction.axisLabels, id: \.key) { axis in
                axisRow(key: axis.key, label: axis.label, hint: axis.hint)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func axisRow(key: String, label: String, hint: String) -> some View {
        let value = axisScores[key] ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                    Text(hint)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { i in
                        Button {
                            withAnimation(.easeOut(duration: 0.12)) {
                                axisScores[key] = i
                            }
                        } label: {
                            Image(systemName: i <= value ? "star.fill" : "star")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(
                                    i <= value
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.textTertiary)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Comment + anonymous

    private var commentCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("COMMENT (OPTIONAL)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text("\(comment.count)/500")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
            TextField("What stood out — good or bad?",
                      text: $comment,
                      axis: .vertical)
                .lineLimit(3, reservesSpace: true)
                .font(EType.body)
                .padding(Space.s3)
                .background(palette.bgCardSoft,
                            in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(palette.borderFaint))
                .onChange(of: comment) { _, newVal in
                    if newVal.count > 500 {
                        comment = String(newVal.prefix(500))
                    }
                }

            Toggle(isOn: $anonymous) {
                Text("Submit anonymously")
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
            }
            .tint(Brand.success)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Submit bar

    private var submitBar: some View {
        VStack(spacing: 0) {
            IridescentHairline()
            HStack(spacing: Space.s3) {
                Button {
                    dismiss()
                } label: {
                    Text("Skip for now")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCard,
                                    in: RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(palette.borderSoft))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)

                CTAButton(
                    title: inFlight ? "Submitting…" : "Submit rating",
                    action: { Task { await submit() } },
                    isLoading: inFlight
                )
                .opacity(canSubmit ? 1.0 : 0.55)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
    }

    private var canSubmit: Bool {
        overall >= 1 && !inFlight
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md)
            .strokeBorder(Brand.danger.opacity(0.4)))
    }

    // MARK: - Submit

    private func submit() async {
        guard canSubmit else { return }
        inFlight = true
        error = nil
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await EusoTripAPI.shared.ratings.submit(
                entityType: "user",
                entityId: counterpartyId,
                loadId: loadId,
                overallRating: overall,
                categories: axisScores.isEmpty ? nil : axisScores,
                comment: trimmedComment.isEmpty ? nil : trimmedComment,
                anonymous: anonymous
            )
            inFlight = false
            withAnimation { success = true }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch {
            inFlight = false
            let ns = error as NSError
            // Server returns CONFLICT when the same (from, to, load)
            // tuple was already rated — surface the readable copy.
            self.error = ns.localizedDescription
        }
    }
}

// MARK: - Previews

#Preview("Driver rates shipper · Dark") {
    RatingPromptView(
        direction: .driverRatesShipper,
        counterpartyId: "1",
        counterpartyName: "Eusorone Technologies",
        loadId: "44912",
        laneSummary: "Houston, TX → Dallas, TX"
    )
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("Shipper rates driver · Light") {
    RatingPromptView(
        direction: .shipperRatesDriver,
        counterpartyId: "12",
        counterpartyName: "Michael Eusorone",
        loadId: "44912",
        laneSummary: "Houston, TX → Dallas, TX"
    )
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
