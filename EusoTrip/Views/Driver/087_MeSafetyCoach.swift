//
//  087_MeSafetyCoach.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · safety coach)
//
//  Screen 087 · Me · Safety Coach — ESANG-powered personalized
//  coaching pack. The driver lands here, sees between 3 and 10 cards
//  that are tailored to their role + vertical + recent compliance
//  signal, and can type a free-text focus ("night driving fog",
//  "new hazmat route") to steer the next refresh.
//
//  Role + vertical parity (doctrine memo 2026-04-24 · "i love all
//  my children"):
//
//    • Server prompt in `esangCoach.forDriver` treats truck, rail,
//      and vessel verticals at equal depth. Rail roles anchor to
//      FRA (49 CFR 240 / 242 / 228 / 236, PTC); vessel roles to
//      USCG + IMO (STCW, ISM, SOLAS, MARPOL, 46 CFR Part 16 drug/
//      alcohol). This screen ships the same density for every role.
//
//    • Hazmat is the most-stringent lens. When the driver's role or
//      record involves hazmat, the server's coaching items surface
//      with the highest regulatory specificity (49 CFR 171-180,
//      §172.704 training, §172.800 security plans, placarding,
//      segregation). The UI honours `severity = critical` for these
//      without any client-side upgrade.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Every coaching card ships from `esangCoach.forDriver`
//      (MCP-verified at `frontend/server/routers/esangCoach.ts:510`,
//      namespace mounted in `frontend/server/routers.ts:1597`).
//
//    • `focus` text box round-trips to the server — we don't
//      transform or prepend; the server is the single source of
//      system-prompt truth. Enter key triggers a refresh.
//
//    • No fallback card rendering. When the server returns an empty
//      items array we branch to `.empty` and show the branded
//      "Quiet day" empty state. Client never fabricates coaching.
//
//    • CFR references render *only* when the server ships them;
//      we do not synthesise CFR numbers on the client per the
//      server's own "never fabricate" prompt rule.
//
//  Modular Ultra design inspiration:
//
//    • The hero uses the circumferential tick-mark aesthetic —
//      short ticks around the top + bottom rails of the hero card —
//      so the screen feels cohesive with the Pulse watch face. This
//      is decorative; the ticks are rendered with Canvas so they
//      do not animate or allocate unless the hero is on screen.
//
//    • Severity chips adopt the watch-face's green / watch-yellow /
//      critical-gradient language so a coach card on the phone
//      reads as the same object a driver would glance at on the
//      wrist.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero numerals + critical chip.
//         Brand.warning on watch chips. Zero flat Brand.info fills.
//    §4   Tokenized spacing (Space.sN), radii (Radius.sm/md/lg),
//         type (EType.*). No magic numbers.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle wrapped in `AnyShapeStyle`.
//    §10  Previews land in `.error` under the no-baseURL runtime.
//         No fixtures.
//

import SwiftUI

// MARK: - Topic → icon mapping

private enum CoachTopic {
    /// Server ships any lowercase slug; anything we don't recognise
    /// falls through to `.other` which uses a neutral lightbulb icon.
    /// Never render a made-up CFR or topic-specific affordance for an
    /// unknown slug.
    static func icon(for topic: String) -> String {
        switch topic.lowercased() {
        case "hos":                 return "clock"
        case "hazmat":              return "exclamationmark.triangle"
        case "following":           return "car.2"
        case "fatigue":             return "bed.double"
        case "weather":             return "cloud.sun"
        case "vehicle":             return "wrench.and.screwdriver"
        case "inspection":          return "checkmark.shield"
        case "training":            return "graduationcap"
        case "fra_certification":   return "train.side.front.car"
        case "stcw":                return "ferry"
        case "mmc_medical":         return "cross.case"
        case "ptc":                 return "wave.3.right"
        case "cargo_securement":    return "shippingbox"
        case "stowage":             return "square.stack.3d.up"
        case "docs":                return "doc.text"
        default:                    return "lightbulb"
        }
    }
}

// MARK: - Severity

private enum CoachSeverity {
    case info, watch, critical

    init(_ raw: String) {
        switch raw.lowercased() {
        case "critical": self = .critical
        case "watch":    self = .watch
        default:         self = .info
        }
    }

    var label: String {
        switch self {
        case .info:     return "Heads-up"
        case .watch:    return "Watch"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Screen root

struct MeSafetyCoach: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = SafetyCoachStore()
    @FocusState private var focusFieldActive: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                focusCard
                switch store.state {
                case .loading:
                    skeleton
                case .empty:
                    quietDayEmpty
                case .error(let e):
                    errorBanner(e)
                case .loaded(let pack):
                    heroSummary(pack)
                    coachList(pack)
                }
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Safety Coach")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESANG · role + vertical aware")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Focus input card

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("WHAT'S ON YOUR MIND")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                Image(systemName: "text.bubble")
                    .foregroundStyle(palette.textSecondary)
                TextField(
                    "e.g. night fog on I-80, first hazmat route, STCW refresher",
                    text: $store.focus,
                    axis: .vertical
                )
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .focused($focusFieldActive)
                .submitLabel(.go)
                .onSubmit {
                    Task { await store.refresh() }
                }
                .lineLimit(1...2)
                if !store.focus.isEmpty {
                    Button {
                        store.focus = ""
                        focusFieldActive = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.4))
            )

            HStack(spacing: Space.s2) {
                limitChip(3)
                limitChip(6)
                limitChip(10)
                Spacer()
                Button {
                    focusFieldActive = false
                    Task { await store.refresh() }
                } label: {
                    Label("Coach me", systemImage: "sparkles")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s2)
                        .background(Capsule().fill(LinearGradient.diagonal))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func limitChip(_ n: Int) -> some View {
        let selected = store.limit == n
        return Button {
            store.limit = n
            Task { await store.refresh() }
        } label: {
            Text("\(n)")
                .font(EType.caption)
                .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textSecondary))
                .frame(minWidth: 30)
                .padding(.vertical, 6)
                .padding(.horizontal, Space.s2)
                .background(
                    Capsule()
                        .fill(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral.opacity(0.55)))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Hero summary

    private func heroSummary(_ pack: EsangCoachAPI.ForDriverResponse) -> some View {
        VStack(spacing: Space.s3) {
            tickCircumference
                .frame(height: 12)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pack.items.count) TAILORED ITEMS")
                        .font(EType.micro)
                        .tracking(1.3)
                        .foregroundStyle(palette.textTertiary)
                    Text(Self.roleLabel(for: pack.role))
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text(Self.verticalLabel(for: pack.vertical))
                        .font(EType.caption)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Self.relativeTime(epochMillis: pack.generatedAt))
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                    Text("UPDATED")
                        .font(EType.micro)
                        .tracking(1.3)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            tickCircumference
                .frame(height: 12)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    /// Modular Ultra-style tick-mark rail, rendered with Canvas so it
    /// doesn't allocate Shape views. Short ticks between rail marks.
    private var tickCircumference: some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            let longTickH = size.height * 0.6
            let shortTickH = size.height * 0.3
            let count = 40
            let step = size.width / CGFloat(count)
            for i in 0...count {
                let x = CGFloat(i) * step
                let isMajor = (i % 10 == 0)
                let h = isMajor ? longTickH : shortTickH
                let rect = CGRect(
                    x: x - 0.5,
                    y: midY - h / 2,
                    width: 1,
                    height: h
                )
                let color: Color = isMajor ? .white.opacity(0.9) : .white.opacity(0.45)
                ctx.fill(Path(rect), with: .color(color))
            }
        }
    }

    // MARK: Coach list

    private func coachList(_ pack: EsangCoachAPI.ForDriverResponse) -> some View {
        VStack(spacing: Space.s3) {
            ForEach(pack.items) { item in
                coachCard(item)
            }
        }
    }

    private func coachCard(_ item: EsangCoachAPI.CoachingItem) -> some View {
        let severity = CoachSeverity(item.severity)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.55))
                    Image(systemName: CoachTopic.icon(for: item.topic))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(iconStyle(for: severity))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        severityChip(severity)
                    }
                    Text(item.body)
                        .font(EType.body)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            if let cfr = item.cfr, !cfr.isEmpty {
                HStack(spacing: Space.s1) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 11, weight: .medium))
                    Text(cfr)
                        .font(EType.caption)
                }
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(palette.tintNeutral.opacity(0.55))
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func iconStyle(for severity: CoachSeverity) -> AnyShapeStyle {
        switch severity {
        case .critical: return AnyShapeStyle(LinearGradient.diagonal)
        case .watch:    return AnyShapeStyle(Brand.warning)
        case .info:     return AnyShapeStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private func severityChip(_ s: CoachSeverity) -> some View {
        switch s {
        case .critical:
            Text(s.label.uppercased())
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(LinearGradient.diagonal)
                )
        case .watch:
            Text(s.label.uppercased())
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 3)
                .overlay(
                    Capsule().stroke(Brand.warning.opacity(0.8), lineWidth: 1)
                )
        case .info:
            Text(s.label.uppercased())
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 3)
                .overlay(
                    Capsule().stroke(palette.textTertiary.opacity(0.55), lineWidth: 1)
                )
        }
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.45))
                .frame(height: 110)
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 96)
            }
        }
    }

    private var quietDayEmpty: some View {
        EusoEmptyState(
            systemImage: "checkmark.seal",
            title: "Quiet day — no coaching needed right now",
            subtitle: "ESANG didn't find anything worth flagging for your role + recent signal. Pull to refresh, or type a focus above to request a specific topic."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't reach ESANG Coach")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var disclosureFooter: some View {
        VStack(spacing: Space.s1) {
            Text("ESANG coaching is advisory — it does not replace your carrier's safety program, your doctor, or an official regulatory opinion.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Text("Hazmat coaching always cites the tightest applicable CFR (49 CFR 171-180, 33 CFR 160, IMDG) when the server flags it.")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.s2)
    }

    // MARK: - Helpers

    private static func roleLabel(for role: String) -> String {
        let r = role.uppercased().replacingOccurrences(of: "_", with: " ")
        return r.capitalized(with: Locale(identifier: "en_US"))
    }

    private static func verticalLabel(for vertical: String) -> String {
        switch vertical.lowercased() {
        case "truck":  return "Truck · FMCSA + FMCSR"
        case "rail":   return "Rail · FRA + STB + PTC"
        case "vessel": return "Vessel · USCG + IMO + IMDG"
        case "cross":  return "Cross-modal · all verticals"
        default:       return vertical.capitalized
        }
    }

    private static func relativeTime(epochMillis: Double) -> String {
        let ts = Date(timeIntervalSince1970: epochMillis / 1000.0)
        let seconds = -ts.timeIntervalSinceNow
        if seconds < 60        { return "just now" }
        if seconds < 3600      { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400    { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86_400))d ago"
    }
}

// MARK: - Screen wrapper

struct MeSafetyCoachScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeSafetyCoach()
        } nav: {
            BottomNav(
                leading: driverNavLeading_087(),
                trailing: driverNavTrailing_087(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_087() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_087() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill",      isCurrent: true)]
}

// MARK: - Previews

#Preview("087 · Safety Coach · Night") {
    MeSafetyCoachScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("087 · Safety Coach · Afternoon") {
    MeSafetyCoachScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
