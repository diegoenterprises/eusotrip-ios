//
//  410_DispatcherExceptionTriage.swift
//  EusoTrip — Dispatcher · Exception Triage.
//
//  Verbatim SwiftUI port of:
//    `04 Dispatcher/Dark-SVG/410 Dispatcher Exception Triage.svg`
//
//  THE EXCEPTION TRIAGE SURFACE — when something breaks (a check-call goes
//  silent, a load ages unassigned) the dispatcher sees every exception ranked
//  by severity and acts in seconds. A severity selector, a stack of
//  severity-rimmed exception cards (Critical → Warning → advisory), an ESANG
//  triage suggestion, and an honest "today" clearance band. Reached by deep
//  link from Home (400) / Board (401).
//
//  Honest wiring — 0 stubs, 0 mock data, fully dynamic:
//    • READ  dispatch.getExceptions      (dispatch.ts:2231, query,
//            {status?,filter?}) → [{ id, type, severity(critical|warning|
//            info), loadNumber, message, status, createdAt, transportMode,
//            multiVehicleCount }]. Every card field is a real exception field
//            — the severity rim, the humanized type, the time-relative age,
//            the mode badge, and the message detail line.
//    • READ  dispatch.getExceptionStats  (dispatch.ts:2315, query) →
//            { open, investigating, resolved, critical, inProgress,
//            resolvedToday }. Drives the selector counts + the today band.
//    • The reads flow through a real do/catch with a surfaced error; the
//      screen shows the error state, never a fake success. Empty →
//      honest "all clear" state.
//    • ASSIGN routes to the real per-load assign surface (532 Assign Driver
//      M05, gated dispatch.assignDriver dispatch.ts:1220); TRACK opens the
//      registered dispatch board (Disp401). No dead taps — the SVG's
//      "Team-up relay" / "Call" chips are omitted (no endpoint) rather than
//      shipped as fake buttons.
//
//  HONEST GAP: there is no hourly exception-history series endpoint, so the
//  SVG's 24-bar trend sparkline is replaced by a real today-clearance band
//  (resolvedToday vs open) from getExceptionStats — no fabricated series.
//  The per-exception HOS "drive left / trip needs / delta" clock the SVG
//  shows for an HOS-breach card is not emitted by getExceptions (which emits
//  check-call-overdue + unassigned-aging), so cards render the real message
//  detail rather than an invented HOS delta.
//
//  Persona: Aurora Freight Lines · Renée Marquette (RM) dispatcher.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: ─────────────────────────────────────────────────────────
// MARK: Decoders — field-for-field match to dispatch.getExceptions / …Stats
// MARK: ─────────────────────────────────────────────────────────

private struct DispatchException: Decodable, Hashable, Identifiable {
    let id: String
    let type: String
    let severity: String        // "critical" | "warning" | "info"
    let loadNumber: String?
    let message: String?
    let status: String?
    let createdAt: String?
    let transportMode: String?
    let multiVehicleCount: Int?
}

private struct ExceptionStats: Decodable, Hashable {
    let open: Int
    let investigating: Int
    let resolved: Int
    let critical: Int
    let inProgress: Int
    let resolvedToday: Int
}

private enum SeverityFilter: String, CaseIterable {
    case all, critical, warning, resolved
    var title: String {
        switch self {
        case .all: return "All"
        case .critical: return "Critical"
        case .warning: return "Warning"
        case .resolved: return "Resolved"
        }
    }
    var dot: Color? {
        switch self {
        case .all: return nil
        case .critical: return Brand.danger
        case .warning: return Brand.warning
        case .resolved: return Brand.success
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Screen
// MARK: ─────────────────────────────────────────────────────────

struct DispatcherExceptionTriageScreen: View {
    let theme: Theme.Palette
    var body: some View {
        // BOARD-relative (reached by deep link from 400/401).
        Shell(theme: theme) { DispatcherExceptionTriageBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",                  isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct DispatcherExceptionTriageBody: View {
    @Environment(\.palette) private var palette

    @State private var exceptions: [DispatchException] = []
    @State private var stats: ExceptionStats = ExceptionStats(open: 0, investigating: 0, resolved: 0, critical: 0, inProgress: 0, resolvedToday: 0)
    @State private var filter: SeverityFilter = .all
    @State private var loading: Bool = true
    @State private var actionError: String?

    private var criticalCount: Int { exceptions.filter { $0.severity == "critical" }.count }
    private var warningCount:  Int { exceptions.filter { $0.severity == "warning"  }.count }

    private var visible: [DispatchException] {
        let live = exceptions.sorted { Triage.rank($0.severity) < Triage.rank($1.severity) }
        switch filter {
        case .all:      return live
        case .critical: return live.filter { $0.severity == "critical" }
        case .warning:  return live.filter { $0.severity == "warning" }
        case .resolved: return []   // resolved history isn't returned by getExceptions
        }
    }

    // Real ESANG triage line derived from the live exception set.
    private var esangLine: (headline: String, detail: String)? {
        guard !exceptions.isEmpty else { return nil }
        if let oldestCritical = exceptions.filter({ $0.severity == "critical" })
            .min(by: { Triage.age($0.createdAt) > Triage.age($1.createdAt) }) {
            return ("Clear the \(criticalCount) critical load\(criticalCount == 1 ? "" : "s") first",
                    "\(oldestCritical.loadNumber ?? "Oldest") is \(Triage.ageLabel(oldestCritical.createdAt)) stale")
        }
        return ("\(exceptions.count) open exception\(exceptions.count == 1 ? "" : "s") to work",
                "no criticals — clear the warnings before they escalate")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline().padding(.top, Space.s3)

                if loading {
                    TriageSkeleton().padding(.top, Space.s5)
                } else if let err = actionError {
                    errorState(err)
                } else {
                    selectorRow
                    if visible.isEmpty {
                        clearState
                    } else {
                        cards
                    }
                    if let e = esangLine { esangStrip(e) }
                    todayBand
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await load() }
    }

    // MARK: Top bar — eyebrow + big title + RM disc + sub

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ DISPATCHER · EXCEPTIONS · LIVE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text("\(stats.open) OPEN · \(stats.critical) CRITICAL")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(stats.critical > 0 ? Brand.danger : palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Button { back() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                Text("Exceptions")
                    .font(EType.display).tracking(-0.6)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                avatarDisc
            }
            Text("\(stats.open) open · \(stats.critical) critical · \(stats.resolvedToday) cleared today")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var avatarDisc: some View {
        ZStack {
            Circle().fill(LinearGradient.diagonal)
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
                                     center: .init(x: 0.35, y: 0.30), startRadius: 0, endRadius: 22))
                .frame(width: 30, height: 30)
                .offset(x: -6, y: -6)
            Text("RM")
                .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
    }

    // MARK: Severity selector

    private var selectorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(SeverityFilter.allCases, id: \.self) { f in
                    selectorPill(f)
                }
            }
        }
        .padding(.top, Space.s5)
    }

    private func selectorCount(_ f: SeverityFilter) -> Int {
        switch f {
        case .all: return exceptions.count
        case .critical: return criticalCount
        case .warning: return warningCount
        case .resolved: return stats.resolvedToday
        }
    }

    private func selectorPill(_ f: SeverityFilter) -> some View {
        let selected = filter == f
        return Button { filter = f } label: {
            HStack(spacing: 6) {
                if let dot = f.dot {
                    Circle().fill(dot).frame(width: 8, height: 8)
                }
                Text("\(f.title) · \(selectorCount(f))")
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(selected ? palette.textOnGradient : palette.textPrimary)
            }
            .padding(.horizontal, Space.s3).frame(height: 32)
            .background {
                if selected {
                    Capsule().fill(LinearGradient.primary)
                } else {
                    Capsule().fill(palette.bgCardSoft)
                    Capsule().strokeBorder(palette.borderFaint, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Cards

    private var cards: some View {
        VStack(spacing: Space.s4) {
            ForEach(visible) { ex in
                ExceptionCard(ex: ex,
                              onPrimary: { primaryAction(ex) },
                              onTrack:   { track(ex) })
            }
        }
        .padding(.top, Space.s5)
    }

    private var clearState: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Brand.success)
            Text(filter == .resolved ? "Resolved history lives on the board" : "All clear")
                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text(filter == .resolved
                 ? "\(stats.resolvedToday) cleared today. Open the board for the full audit trail."
                 : "No open exceptions in this view. ESANG will surface new ones the moment they trip.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s7).padding(.horizontal, Space.s4)
        .background(RoundedRectangle(cornerRadius: 20).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(palette.borderFaint, lineWidth: 1))
        .padding(.top, Space.s5)
    }

    // MARK: ESANG triage strip

    private func esangStrip(_ e: (headline: String, detail: String)) -> some View {
        HStack(spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("ESANG · \(e.headline)")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(e.detail)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1))
        .padding(.top, Space.s5)
    }

    // MARK: Today clearance band (honest — replaces fabricated 24h sparkline)

    private var todayBand: some View {
        let cleared = stats.resolvedToday
        let open = stats.open
        let total = max(1, cleared + open)
        let clearedFrac = CGFloat(cleared) / CGFloat(total)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("TODAY · CLEARED VS OPEN")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("cleared \(cleared) · open \(open)")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.warning.opacity(0.25))
                    Capsule().fill(LinearGradient.diagonal)
                        .frame(width: max(6, geo.size.width * clearedFrac))
                }
            }
            .frame(height: 8)
        }
        .padding(.top, Space.s6)
    }

    // MARK: Error state

    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Couldn't load exceptions").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            Button { Task { await load() } } label: {
                Text("Retry").font(EType.caption.weight(.heavy))
                    .foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, Space.s4).frame(height: 32)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain).padding(.top, Space.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .padding(.top, Space.s5)
    }

    // MARK: Data + actions

    private func load() async {
        loading = true
        actionError = nil
        struct In: Encodable {}
        do {
            async let exCall: [DispatchException] = EusoTripAPI.shared.query("dispatch.getExceptions", input: In())
            async let stCall: ExceptionStats = EusoTripAPI.shared.queryNoInput("dispatch.getExceptionStats")
            let (ex, st) = try await (exCall, stCall)
            exceptions = ex
            stats = st
        } catch {
            actionError = "Exceptions couldn't refresh. Retry from this screen or open the dispatch board."
        }
        loading = false
    }

    private func primaryAction(_ ex: DispatchException) {
        if ex.type == "unassigned_aging" {
            // Open the per-load assign surface (532 Assign Driver M05).
            NotificationCenter.default.post(
                name: .eusoDispatchNavSwap, object: nil,
                userInfo: ["screenId": "532", "loadNumber": ex.loadNumber ?? ""]
            )
        } else {
            track(ex)
        }
    }

    private func track(_ ex: DispatchException) {
        NotificationCenter.default.post(name: .eusoDispatchNavSwap, object: nil, userInfo: ["screenId": "Disp401"])
    }

    private func back() {
        NotificationCenter.default.post(name: .eusoDispatchNavSwap, object: nil, userInfo: ["screenId": "Disp401"])
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Exception card (severity-rimmed)
// MARK: ─────────────────────────────────────────────────────────

private struct ExceptionCard: View {
    @Environment(\.palette) private var palette
    let ex: DispatchException
    let onPrimary: () -> Void
    let onTrack: () -> Void

    private var isCritical: Bool { ex.severity == "critical" }
    private var accent: Color {
        switch ex.severity {
        case "critical": return Brand.danger
        case "warning":  return Brand.warning
        default:         return palette.textTertiary
        }
    }
    private var severityLabel: String {
        switch ex.severity {
        case "critical": return "CRITICAL"
        case "warning":  return "WARNING"
        default:         return "ADVISORY"
        }
    }
    private var typeLabel: String { Triage.humanType(ex.type) }
    private var primaryLabel: String { ex.type == "unassigned_aging" ? "Assign driver" : "Track load" }
    private var modeBadge: String? {
        guard let m = ex.transportMode?.lowercased(), m != "truck" else { return nil }
        return m.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Severity strip
            HStack(spacing: Space.s2) {
                Text(ex.severity == "critical" ? "P0" : (ex.severity == "warning" ? "P1" : "P2"))
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(accent))
                Text(typeLabel)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Space.s2)
                if isCritical {
                    Circle().fill(accent).frame(width: 7, height: 7)
                }
                Text(Triage.ageLabel(ex.createdAt))
                    .font(EType.mono(.caption))
                    .foregroundStyle(accent)
            }

            // Subject line — loadNumber + mode
            HStack(spacing: Space.s2) {
                Text(ex.loadNumber ?? "—")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                if let m = modeBadge {
                    Text(m)
                        .font(EType.micro).tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).frame(height: 18)
                        .background(Capsule().fill(ex.transportMode?.lowercased() == "rail" ? Brand.rail : Brand.vessel))
                }
            }

            // Message detail (the real exception body)
            Text(ex.message ?? severityLabel.capitalized)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Action row
            HStack(spacing: Space.s3) {
                Button(action: onPrimary) {
                    Text(primaryLabel)
                        .font(EType.caption.weight(.heavy))
                        .foregroundStyle(palette.textOnGradient)
                        .padding(.horizontal, Space.s4).frame(height: 34)
                        .background(Capsule().fill(LinearGradient.primary))
                }
                .buttonStyle(.plain)
                Button(action: onTrack) {
                    Text("View on board")
                        .font(EType.caption.weight(.heavy))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, Space.s4).frame(height: 34)
                        .background(Capsule().fill(Color(hex: 0x232932)))
                        .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(palette.bgCardSoft))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(isCritical ? AnyShapeStyle(LinearGradient(colors: [Brand.danger, Brand.warning],
                                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                         : AnyShapeStyle(accent.opacity(0.55)),
                              lineWidth: isCritical ? 1.75 : 1)
        )
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Skeleton
// MARK: ─────────────────────────────────────────────────────────

private struct TriageSkeleton: View {
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: Space.s4) {
            HStack(spacing: Space.s2) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule().fill(palette.bgCardSoft).frame(width: 72, height: 32)
                }
            }
            RoundedRectangle(cornerRadius: 20).fill(palette.bgCardSoft).frame(height: 168)
            RoundedRectangle(cornerRadius: 20).fill(palette.bgCardSoft).frame(height: 128)
        }
        .redacted(reason: .placeholder)
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Triage helpers
// MARK: ─────────────────────────────────────────────────────────

private enum Triage {
    static func rank(_ severity: String) -> Int {
        switch severity {
        case "critical": return 0
        case "warning":  return 1
        default:         return 2
        }
    }

    static func humanType(_ type: String) -> String {
        switch type {
        case "check_call_overdue": return "Check-call overdue"
        case "unassigned_aging":   return "Unassigned · aging"
        default:
            return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    static func age(_ iso: String?) -> TimeInterval {
        guard let d = date(iso) else { return 0 }
        return max(0, Date().timeIntervalSince(d))
    }

    static func ageLabel(_ iso: String?) -> String {
        let secs = Int(age(iso))
        if secs < 60 { return "just now" }
        let m = secs / 60
        if m < 60 { return "\(m)m ago" }
        let h = m / 60
        if h < 24 { return "\(h)h \(m % 60)m ago" }
        return "\(h / 24)d ago"
    }
}

#if DEBUG
#Preview("410 · Dispatcher Exception Triage · Dark") {
    DispatcherExceptionTriageScreen(theme: Theme.dark)
        .environment(\.palette, Theme.dark)
}
#Preview("410 · Dispatcher Exception Triage · Light") {
    DispatcherExceptionTriageScreen(theme: Theme.light)
        .environment(\.palette, Theme.light)
}
#endif
