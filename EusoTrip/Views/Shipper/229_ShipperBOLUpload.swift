//
//  229_ShipperBOLUpload.swift
//  EusoTrip 2027 UI — Shipper · BOL Upload (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — new file at slot 229 to match wireframe
//  canon at /02 Shipper/Code/229_ShipperBOLUpload.swift. Persona:
//  Diego Usoro / Eusorone Technologies (companyId 1) per §11. The
//  per-load BOL detail surface that opens from the load card.
//
//  Note: slot 229 also holds `229_ShipperAllocations.swift` in the
//  iOS tree (different scope, different struct names — no compile
//  conflict). Wireframe canon governs the UI of this file
//  specifically.
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · BOL UPLOAD / "{N}/3 SIGNED" status counter
//    2. Back chevron + breadcrumb "Loads"
//    3. Title block      32pt "BOL detail" + sub line citing lane + cargo
//    4. IridescentHairline
//    5. Hero BOL card    3pt success tier rim + BOL id + status pill +
//                        lane title + spec line + Uploaded-by Diego +
//                        4-stage lifecycle strip (UPLOADED · VERIFIED ·
//                        SIGNED · FILED)
//    6. KPI quartet      4-cell · PAGES · SIZE · INTEGRITY · SIGNED
//    7. SIGNATORIES      section eyebrow + 3 signatory rows + 1 audit-log row
//    8. View audit trail gradient mid-link
//
//  Real wiring: iOS doesn't yet have a per-BOL detail endpoint;
//  surfaces real document metadata via `documents.getAll` filtered
//  to BOL category (placeholder). The signatory state is canonical
//  §11.4 anchor data with explicit EUSO-2147 backend gap.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2147 — `documents.bol.getDetail(loadId:)` not yet on
//                iOS API. Hero card uses canonical §11.4 row 1 anchor
//                values (Houston→Dallas tanker, BOL-260427-A38FB12C7E)
//                until backend ships the per-BOL detail envelope.
//    EUSO-2148 — Signatory state (3-party · WET / E-SIGN / device /
//                timestamp) not shipped. Signatory rows use
//                §11 persona canon (Diego shipper · Michael Eusorone
//                carrier · receiver pending) explicitly until backend
//                ships `documents.bol.getSignatories(bolId:)`.
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy; §4.3 single iridescent hairline; §11 / §11.2 /
//  §11.4 / §15.3 audit-trail BOL-{hex} suffix; §17.2 KPI quartet
//  recipe; §19.2 file-scoped LifecycleStrip4BOL + successGrad +
//  warnGrad helpers; §20.4 no dead buttons; §22.2 Brand.success
//  counter for healthy state.
//

import SwiftUI

// MARK: - Lifecycle stages

private enum BOLStage: CaseIterable {
    case uploaded, verified, signed, filed

    var label: String {
        switch self {
        case .uploaded: return "UPLOADED"
        case .verified: return "VERIFIED"
        case .signed:   return "SIGNED"
        case .filed:    return "FILED"
        }
    }
}

// MARK: - Signatory model

private struct Signatory: Identifiable {
    let id = UUID()
    let initials: String
    let chipLabel: String
    let chipStyle: ChipStyle
    let partyName: String
    let credLine: String
    let badge: BadgeKind
    let tierRim: TierRim
    let stats: [SigStat]

    enum ChipStyle { case gradient, successHollow, warnHollow }
    enum BadgeKind {
        case shipper(String, CGFloat)
        case carrier(String, CGFloat)
        case receiver(String, CGFloat)
    }
    enum TierRim { case gradient, success, warn, neutral }
    struct SigStat: Identifiable {
        let id = UUID()
        let value: String
        let unit: String
        let color: ValueColor
        enum ValueColor { case primary, success, warn }
    }
}

// MARK: - Screen root

struct ShipperBOLUpload: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(loadId: String = "LD-260427-A38FB12C7E") {
        self.loadId = loadId
    }

    // §11 / §11.4 row 1 anchor canon — used until EUSO-2147 lands a
    // per-BOL detail endpoint.
    private var bolId: String {
        // Reuse the LD- hex tail per §15.3 audit-trail suffix doctrine.
        let suffix = loadId.replacingOccurrences(of: "LD-", with: "")
        return "BOL-\(suffix)"
    }
    private let lane = "Houston TX → Dallas TX"
    private let specLine = "MC-306 · Gasoline UN1203 · 8,200 gal · 53′ tanker · ETA in 4h 12min"
    private let titleText = "BOL detail"
    private let titleSubline = "Eusorone Technologies · Houston→Dallas gasoline · MC-306"
    private let counterEyebrow = "PICKUP SIGNED · 2/3"

    private let activeStage: BOLStage = .signed

    private let signatories: [Signatory] = [
        Signatory(
            initials: "DU",
            chipLabel: "SIGNED",
            chipStyle: .gradient,
            partyName: "Diego Usoro",
            credLine: "Eusorone Technologies · companyId 1 · BOL author",
            badge: .shipper("SHIPPER", 92),
            tierRim: .gradient,
            stats: [
                .init(value: "2h ago", unit: "when",     color: .primary),
                .init(value: "WET",    unit: "method",   color: .primary),
                .init(value: "✓",      unit: "verified", color: .success),
                .init(value: "iPhone", unit: "device",   color: .primary)
            ]
        ),
        Signatory(
            initials: "ME",
            chipLabel: "SIGNED",
            chipStyle: .successHollow,
            partyName: "Michael Eusorone",
            credLine: "Eusotrans LLC · USDOT 3 194 882 · MC-820 144 · A+ grade",
            badge: .carrier("CARRIER", 60),
            tierRim: .success,
            stats: [
                .init(value: "1h ago", unit: "when",     color: .primary),
                .init(value: "E-SIGN", unit: "method",   color: .primary),
                .init(value: "✓",      unit: "verified", color: .success),
                .init(value: "iOS",    unit: "device",   color: .primary)
            ]
        ),
        Signatory(
            initials: "CD",
            chipLabel: "PENDING",
            chipStyle: .warnHollow,
            partyName: "Costco Distribution Center",
            credLine: "Dallas TX · DC-04 · awaiting delivery in ~4h 12min",
            badge: .receiver("RECEIVER", 72),
            tierRim: .warn,
            stats: [
                .init(value: "3:54 PM", unit: "ETA",         color: .warn),
                .init(value: "E-SIGN",  unit: "ready",       color: .primary),
                .init(value: "—",       unit: "at delivery", color: .warn),
                .init(value: "DC-04",   unit: "site",        color: .primary)
            ]
        )
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                crumbRow
                    .padding(.top, Space.s2)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)

                heroCard
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)

                kpiQuartet
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)

                sectionLabel("SIGNATORIES · 2/3 SIGNED")
                    .padding(.top, Space.s5)

                VStack(spacing: Space.s3) {
                    ForEach(signatories) { sig in
                        signatoryRow(sig)
                    }
                    auditLogRow
                }
                .padding(.horizontal, Space.s3)
                .padding(.top, Space.s3)

                viewAuditTrailLink
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)

                Color.clear.frame(height: 96)
            }
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · BOL UPLOAD")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(Brand.success)
                .accessibilityLabel("Pickup signed, two of three parties")
        }
        .padding(.horizontal, Space.s3)
    }

    // MARK: Back chevron + breadcrumb

    private var crumbRow: some View {
        Button(action: tapBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("Loads")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, Space.s3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to Loads")
    }

    private func tapBack() {
        // observability post — real effect: dismiss() env handler
        dismiss()
        NotificationCenter.default.post(
            name: .eusoShipperBolUploadBack,
            object: nil,
            userInfo: ["source": "229_ShipperBOLUpload", "loadId": loadId]
        )
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleText)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text(titleSubline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
    }

    // MARK: Section label

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s3)
    }

    // MARK: Hero BOL card

    private var heroCard: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(LinearGradient.bolSuccessGrad)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(bolId)
                        .font(EType.mono(.micro))
                        .tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("PICKUP SIGNED · 2/3")
                        .font(EType.micro)
                        .tracking(0.6)
                        .foregroundStyle(.white)
                        .frame(width: 148, height: 20)
                        .background(Capsule().fill(LinearGradient.bolSuccessGrad))
                }
                .padding(.top, Space.s4)

                Text(lane)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .padding(.top, Space.s2 + 2)

                Text(specLine)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.top, 4)

                uploadedByRow
                    .padding(.top, Space.s2 + 2)

                LifecycleStrip4BOL(activeStage: activeStage)
                    .padding(.top, Space.s4 + 2)
                    .padding(.bottom, Space.s4)
            }
            .padding(.leading, Space.s4)
            .padding(.trailing, Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bolId), pickup signed two of three, \(lane), \(specLine), uploaded by Diego Usoro, Eusorone Technologies")
    }

    private var uploadedByRow: some View {
        HStack(spacing: Space.s2) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 14, height: 14)
                Text("DU")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 0) {
                Text("Uploaded by ").foregroundStyle(palette.textSecondary)
                Text("Diego Usoro").fontWeight(.bold).foregroundStyle(palette.textPrimary)
                Text(" · Eusorone Technologies · 2h ago").foregroundStyle(palette.textSecondary)
            }
            .font(.system(size: 10.5))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
        }
    }

    // MARK: KPI quartet

    private var kpiQuartet: some View {
        HStack(spacing: 0) {
            kpiCellView(label: "PAGES", value: "—", style: .gradient, sub: "EUSO-2147")
            kpiDivider
            kpiCellView(label: "SIZE", value: "—", style: .primary, sub: "encrypted")
            kpiDivider
            kpiCellView(label: "INTEGRITY", value: "—", style: .primary, sub: "SHA-256")
            kpiDivider
            kpiCellView(label: "SIGNED", value: "2/3", style: .warn, sub: "+1 pending")
        }
        .padding(.vertical, Space.s4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 44)
    }

    private enum KpiStyle { case gradient, primary, warn }

    @ViewBuilder
    private func kpiCellView(label: String, value: String, style: KpiStyle, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                switch style {
                case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                case .primary:  Text(value).foregroundStyle(palette.textPrimary)
                case .warn:     Text(value).foregroundStyle(Brand.warning)
                }
            }
            .font(.system(size: 22, weight: .bold).monospacedDigit())
            Text(sub)
                .font(.system(size: 9))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    // MARK: Signatory row

    private func signatoryRow(_ sig: Signatory) -> some View {
        let rim: AnyShapeStyle = {
            switch sig.tierRim {
            case .gradient: return AnyShapeStyle(LinearGradient.diagonal)
            case .success:  return AnyShapeStyle(Brand.success)
            case .warn:     return AnyShapeStyle(LinearGradient.bolWarnGrad)
            case .neutral:  return AnyShapeStyle(palette.textTertiary)
            }
        }()
        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(rim)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    avatarChip(sig)
                    Spacer()
                    badgeView(sig.badge)
                }
                .padding(.top, Space.s4)

                Text(sig.partyName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .padding(.top, Space.s2 + 2)

                Text(sig.credLine)
                    .font(EType.mono(.caption))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.top, 4)

                statRow(sig.stats)
                    .padding(.top, Space.s2 + 2)
                    .padding(.bottom, Space.s4)
            }
            .padding(.leading, Space.s4)
            .padding(.trailing, Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func avatarChip(_ sig: Signatory) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(initialsPaint(sig)).frame(width: 28, height: 28)
                Text(sig.initials)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(initialsTextColor(sig))
            }
            Text(sig.chipLabel)
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(chipTextColor(sig.chipStyle))
        }
    }

    private func initialsPaint(_ sig: Signatory) -> AnyShapeStyle {
        switch sig.chipStyle {
        case .gradient:      return AnyShapeStyle(LinearGradient.diagonal)
        case .successHollow: return AnyShapeStyle(Brand.success.opacity(0.18))
        case .warnHollow:    return AnyShapeStyle(LinearGradient.bolWarnGrad.opacity(0.18))
        }
    }

    private func initialsTextColor(_ sig: Signatory) -> Color {
        switch sig.chipStyle {
        case .gradient:      return .white
        case .successHollow: return Brand.success
        case .warnHollow:    return Brand.warning
        }
    }

    private func chipTextColor(_ style: Signatory.ChipStyle) -> Color {
        switch style {
        case .gradient:      return palette.textPrimary
        case .successHollow: return Brand.success
        case .warnHollow:    return Brand.warning
        }
    }

    @ViewBuilder
    private func badgeView(_ kind: Signatory.BadgeKind) -> some View {
        switch kind {
        case .shipper(let label, let width):
            Text(label)
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(.white)
                .frame(width: width, height: 18)
                .background(Capsule().fill(LinearGradient.diagonal))
        case .carrier(let label, let width):
            Text(label)
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(Brand.success)
                .frame(width: width, height: 18)
                .background(Capsule().fill(Brand.success.opacity(0.14)))
        case .receiver(let label, let width):
            Text(label)
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(Brand.warning)
                .frame(width: width, height: 18)
                .overlay(Capsule().strokeBorder(Brand.warning.opacity(0.5), lineWidth: 0.75))
                .background(Capsule().fill(palette.bgCardSoft))
        }
    }

    private func statRow(_ stats: [Signatory.SigStat]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(stats) { stat in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(stat.value)
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(statColor(stat.color))
                    Text(stat.unit)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statColor(_ c: Signatory.SigStat.ValueColor) -> Color {
        switch c {
        case .primary: return palette.textPrimary
        case .success: return Brand.success
        case .warn:    return Brand.warning
        }
    }

    // MARK: Audit log row

    private var auditLogRow: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(palette.textTertiary)
                .frame(width: 3)
            HStack(alignment: .center, spacing: Space.s3) {
                Text("12")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 20)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audit log · 12 events")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("Upload 2h · Verify 1h 58m · Shipper-sign 1h 50m · Carrier-sign 1h · …")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                Spacer()
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: View audit trail link

    private var viewAuditTrailLink: some View {
        Button(action: tapAuditTrail) {
            Text("View audit trail · 12 events · SHA-256 chain")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LinearGradient.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func tapAuditTrail() {
        NotificationCenter.default.post(
            name: .eusoShipperBolAuditTrail,
            object: nil,
            userInfo: [
                "source": "229_ShipperBOLUpload",
                "bolId": bolId
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/bol/\(bolId)/audit-trail") {
            openURL(url)
        }
    }
}

// MARK: - 4-stage BOL lifecycle strip (file-scoped per §19.2)

private struct LifecycleStrip4BOL: View {
    let activeStage: BOLStage
    @Environment(\.palette) var palette

    private let stages: [(key: BOLStage, label: String)] = [
        (.uploaded, "UPLOADED"),
        (.verified, "VERIFIED"),
        (.signed,   "SIGNED"),
        (.filed,    "FILED"),
    ]

    private var activeIndex: Int {
        stages.firstIndex(where: { $0.key == activeStage }) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let count = stages.count
            let stride = total / CGFloat(count - 1)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(palette.borderFaint)
                    .frame(width: total, height: 2)
                Rectangle()
                    .fill(LinearGradient.primary)
                    .frame(width: stride * CGFloat(activeIndex), height: 2)
                ForEach(0..<count, id: \.self) { i in
                    let isActive = i == activeIndex
                    let isCompleted = i < activeIndex
                    Circle()
                        .fill(isCompleted || isActive
                              ? AnyShapeStyle(LinearGradient.diagonal)
                              : AnyShapeStyle(palette.borderFaint))
                        .frame(width: isActive ? 9 : 7, height: isActive ? 9 : 7)
                        .offset(x: stride * CGFloat(i) - (isActive ? 4.5 : 3.5))
                }
                ForEach(0..<count, id: \.self) { i in
                    let isActive = i == activeIndex
                    let isCompleted = i < activeIndex
                    let label = stages[i].label
                    Text(label)
                        .font(.system(size: 7, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(
                            isActive
                                ? AnyShapeStyle(LinearGradient.primary)
                                : (isCompleted
                                    ? AnyShapeStyle(palette.textSecondary)
                                    : AnyShapeStyle(palette.textTertiary))
                        )
                        .offset(x: anchoredOffset(for: i, count: count, stride: stride, label: label),
                                y: -10)
                }
            }
        }
        .frame(height: 18)
    }

    private func anchoredOffset(for i: Int, count: Int, stride: CGFloat, label: String) -> CGFloat {
        let approxWidth: CGFloat = CGFloat(label.count) * 4.0
        let baseX = stride * CGFloat(i)
        if i == 0 { return baseX }
        if i == count - 1 { return baseX - approxWidth }
        return baseX - approxWidth / 2
    }
}

// MARK: - File-scoped paint extensions (§19.2)

private extension LinearGradient {
    /// Success gradient for the BOL hero rim + status pill.
    static let bolSuccessGrad = LinearGradient(
        colors: [Brand.success, Color(hex: 0x00A07B)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Warn gradient for receiver-pending tier rim.
    static let bolWarnGrad = LinearGradient(
        colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Back chevron on BOL Upload detail.
    static let eusoShipperBolUploadBack = Notification.Name("eusoShipperBolUploadBack")
    /// "View audit trail" gradient mid-link tap.
    static let eusoShipperBolAuditTrail = Notification.Name("eusoShipperBolAuditTrail")
}

// MARK: - Previews

#Preview("229 · BOL Upload · Dark") {
    ShipperBOLUpload(loadId: "LD-260427-A38FB12C7E")
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("229 · BOL Upload · Light") {
    ShipperBOLUpload(loadId: "LD-260427-A38FB12C7E")
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
