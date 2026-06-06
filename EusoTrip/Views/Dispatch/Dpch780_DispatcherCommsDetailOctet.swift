//
//  Dpch780_DispatcherCommsDetailOctet.swift
//  EusoTrip — Dispatcher · Comms-detail octet (480-487).
//
//  Pixel-match to:
//    480 Dispatcher Comms Review
//    481 Dispatcher Comms Response Time Detail
//    482 Dispatcher Comms SLA Compliance Detail
//    483 Dispatcher Comms Escalation-Free Detail
//    484 Dispatcher Comms Thread Closure Detail
//    485 Dispatcher Comms Thread Volume Detail
//    486 Dispatcher Comms First Touch Resolution Detail
//    487 Dispatcher Comms Quarter Trajectory Detail
//
//  All 8 share `DispatcherCommsBody` parameterized by
//  `DispatcherCommsKind`. Body reads the TYPED `messaging.getConversations`
//  proc (`EusoTripAPI.shared.messaging.getConversations()` →
//  `[MessagingConversation]`) and renders ONLY what that proc actually
//  surfaces: thread count, unread total, and last-activity timing.
//
//  ZERO FABRICATION: the messaging stack has NO SLA grade, response-time
//  p50, escalation count, closure rate, first-touch-resolution, or
//  per-quarter rollup. Those are genuine backend gaps and render an
//  honest "—" / "-" — never an invented literal, EUSORONE ceiling, or
//  §-citation. Identity is the signed-in dispatcher (`session.user`),
//  not a hardcoded persona. Bottom nav frozen (Dispatcher: Home / Board /
//  ESANG / Me).
//

import SwiftUI

enum DispatcherCommsKind: String {
    case review, responseTime, slaCompliance, escalationFree, threadClosure, threadVolume, firstTouchResolution, quarter
}

private struct DCConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
}

private extension DispatcherCommsKind {
    var config: DCConfig {
        switch self {
        case .review:
            return .init(eyebrow: "DISPATCHER · COMMS · REVIEW",
                         citation: "DISPATCHER REVIEW · COMMS THREADS",
                         title: "Comms review",
                         subhead: "Thread inbox · live",
                         pillCopy: "Live thread count, unread total and last-activity timing from the messaging inbox. Per-axis grading is a backend gap.")
        case .responseTime:
            return .init(eyebrow: "DISPATCHER · COMMS · RESPONSE-TIME",
                         citation: "DISPATCHER RESPONSE · COMMS THREADS",
                         title: "Response time",
                         subhead: "Thread inbox · last activity",
                         pillCopy: "Last-activity timing is live from the inbox. Per-class response-time scoring is a backend gap.")
        case .slaCompliance:
            return .init(eyebrow: "DISPATCHER · COMMS · SLA-COMPLIANCE",
                         citation: "DISPATCHER COMPLIANCE · COMMS THREADS",
                         title: "SLA compliance",
                         subhead: "Thread inbox · live",
                         pillCopy: "SLA-compliance grading is a backend gap — no live source. Thread count is live from the inbox.")
        case .escalationFree:
            return .init(eyebrow: "DISPATCHER · COMMS · ESCALATION-FREE",
                         citation: "DISPATCHER ESCALATION · COMMS THREADS",
                         title: "Escalation-free",
                         subhead: "Thread inbox · live",
                         pillCopy: "Escalation tracking is a backend gap — no live source. Thread count is live from the inbox.")
        case .threadClosure:
            return .init(eyebrow: "DISPATCHER · COMMS · THREAD-CLOSURE",
                         citation: "DISPATCHER CLOSURE · COMMS THREADS",
                         title: "Thread closure",
                         subhead: "Thread inbox · live",
                         pillCopy: "Closure-rate grading is a backend gap — no live source. Thread count is live from the inbox.")
        case .threadVolume:
            return .init(eyebrow: "DISPATCHER · COMMS · THREAD-VOLUME",
                         citation: "DISPATCHER VOLUME · COMMS THREADS",
                         title: "Thread volume",
                         subhead: "Thread inbox · live",
                         pillCopy: "Live thread count and unread total from the inbox. Per-week volume rollups are a backend gap.")
        case .firstTouchResolution:
            return .init(eyebrow: "DISPATCHER · COMMS · FIRST-TOUCH-RESOLUTION",
                         citation: "DISPATCHER FTR · COMMS THREADS",
                         title: "First-touch resolution",
                         subhead: "Thread inbox · live",
                         pillCopy: "First-touch-resolution grading is a backend gap — no live source. Thread count is live from the inbox.")
        case .quarter:
            return .init(eyebrow: "DISPATCHER · COMMS · TRAJECTORY",
                         citation: "DISPATCHER COMMS TRAJECTORY · COMMS THREADS",
                         title: "Quarter trajectory",
                         subhead: "Thread inbox · live",
                         pillCopy: "Per-quarter trajectory rollups are a backend gap — no live source. Thread count is live from the inbox.")
        }
    }
}

private struct DispatcherCommsShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.stack.fill", isCurrent: true)],
                trailing: [NavSlot(label: "ESANG", systemImage: "sparkles", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",   isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct DispatcherCommsBody: View {
    let kind: DispatcherCommsKind

    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @State private var threads: [MessagingConversation] = []
    @State private var loaded = false

    // MARK: Live aggregates (typed `messaging.getConversations`)

    /// Thread count straight off the typed proc. No invented floor.
    /// "—" until the first decode completes (genuinely unknown), then 0+.
    private var threadCountText: String { loaded ? "\(threads.count)" : "—" }

    /// Sum of per-conversation unread via the struct's `effectiveUnread`
    /// (`unreadCount ?? unread ?? 0`).
    private var unreadTotal: Int { threads.reduce(0) { $0 + $1.effectiveUnread } }
    private var unreadText: String { loaded ? "\(unreadTotal)" : "—" }

    /// Last-activity timing — newest `lastMessageAt` across the inbox,
    /// rendered as a relative age. This is the only honest "timing" the
    /// proc surfaces. "—" when no thread carries a parseable timestamp.
    private var lastActivityText: String {
        let dates = threads.compactMap { $0.lastMessageAt.flatMap(Self.parseISO) }
        guard let newest = dates.max() else { return "—" }
        return Self.relativeAge.localizedString(for: newest, relativeTo: Date())
    }

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                pill(c)
                identityRow
                kpiGrid
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func header(_ c: DCConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func pill(_ c: DCConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text("THREADS \(threadCountText) · LAST ACTIVITY \(lastActivityText)").font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var identityRow: some View {
        // Identity is the signed-in dispatcher (session), NOT a persona.
        let person = session.user?.name ?? "—"
        let companyTag = session.user?.companyId.map { "companyId · \($0)" } ?? "—"
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 12)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(person) · Comms Threads").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("\(companyTag) · \(threadCountText) threads · \(unreadText) unread").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        // Live cards bind to the typed proc (threads / unread / last
        // activity). Every grading axis with no live source renders "—".
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .review:
                return [
                    ("GRADE",      "—",                   "no live source",        palette.textTertiary),
                    ("RESPONSE",   "—",                   "no live source",        palette.textTertiary),
                    ("THREADS",    threadCountText,       "inbox · live",          .blue),
                    ("UNREAD",     unreadText,             "inbox · live",         .blue),
                ]
            case .responseTime:
                return [
                    ("P50",        "—",                    "no live source",      palette.textTertiary),
                    ("LAST",       lastActivityText,        "inbox · live",       .blue),
                    ("THREADS",    threadCountText,           "inbox · live",     .blue),
                    ("GRADE",      "—",                       "no live source",   palette.textTertiary),
                ]
            case .slaCompliance:
                return [
                    ("SLA",        "—",                          "no live source",  palette.textTertiary),
                    ("BREACH",     "—",                           "no live source", palette.textTertiary),
                    ("THREADS",    threadCountText,                "inbox · live",  .blue),
                    ("GRADE",      "—",                            "no live source", palette.textTertiary),
                ]
            case .escalationFree:
                return [
                    ("ESCAL",      "—",                            "no live source", palette.textTertiary),
                    ("THREADS",    threadCountText,                 "inbox · live",  .blue),
                    ("UNREAD",     unreadText,                       "inbox · live", .blue),
                    ("GRADE",      "—",                              "no live source", palette.textTertiary),
                ]
            case .threadClosure:
                return [
                    ("CLOSED",     "—",                              "no live source", palette.textTertiary),
                    ("OPEN",       "—",                              "no live source", palette.textTertiary),
                    ("THREADS",    threadCountText,                   "inbox · live", .blue),
                    ("GRADE",      "—",                               "no live source", palette.textTertiary),
                ]
            case .threadVolume:
                return [
                    ("VOL/WK",     "—",                               "no live source", palette.textTertiary),
                    ("THREADS",    threadCountText,                    "inbox · live", .blue),
                    ("UNREAD",     unreadText,                          "inbox · live", .blue),
                    ("GRADE",      "—",                                 "no live source", palette.textTertiary),
                ]
            case .firstTouchResolution:
                return [
                    ("FTR",        "—",                                  "no live source", palette.textTertiary),
                    ("PENDING",    "—",                                   "no live source", palette.textTertiary),
                    ("THREADS",    threadCountText,                        "inbox · live", .blue),
                    ("GRADE",      "—",                                    "no live source", palette.textTertiary),
                ]
            case .quarter:
                return [
                    ("YEAR-AVG",   "—",                                    "no live source", palette.textTertiary),
                    ("CEILING",    "—",                                     "no live source", palette.textTertiary),
                    ("THREADS",    threadCountText,                          "inbox · live", .blue),
                    ("GRADE",      "—",                                      "no live source", palette.textTertiary),
                ]
            }
        }()
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.0).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.1).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.3)
                    Text(k.2).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.3.opacity(0.3)))
            }
        }
    }

    private var nextStepCard: some View {
        // Honest guidance: live axis (threads/unread/timing) where the
        // proc supplies it, otherwise name the backend gap plainly.
        let copy: String = {
            switch kind {
            case .review:              return "\(threadCountText) threads, \(unreadText) unread, last activity \(lastActivityText). Per-axis grading is a backend gap."
            case .responseTime:        return "Last activity \(lastActivityText). Per-class response-time scoring is a backend gap — no live source yet."
            case .slaCompliance:       return "SLA-compliance grading is a backend gap — no live source. \(threadCountText) threads in the inbox."
            case .escalationFree:      return "Escalation tracking is a backend gap — no live source. \(threadCountText) threads in the inbox."
            case .threadClosure:       return "Closure-rate grading is a backend gap — no live source. \(threadCountText) threads in the inbox."
            case .threadVolume:        return "\(threadCountText) threads, \(unreadText) unread. Per-week volume rollups are a backend gap."
            case .firstTouchResolution:return "First-touch-resolution grading is a backend gap — no live source. \(threadCountText) threads in the inbox."
            case .quarter:             return "Per-quarter trajectory rollups are a backend gap — no live source. \(threadCountText) threads in the inbox."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func load() async {
        // Bind to the TYPED proc — `[MessagingConversation]`, not a
        // hand-rolled decoder. effectiveUnread / lastMessageAt come off
        // the struct verbatim.
        do { threads = try await EusoTripAPI.shared.messaging.getConversations() } catch { /* leave inbox empty */ }
        loaded = true
    }

    // MARK: Date helpers

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoParserNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static func parseISO(_ s: String) -> Date? {
        isoParser.date(from: s) ?? isoParserNoFrac.date(from: s)
    }
    private static let relativeAge: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// MARK: - Screens (480-487)

struct DispatcherCommsReviewScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherCommsShell(theme: theme) { DispatcherCommsBody(kind: .review) } }
}
struct DispatcherCommsResponseTimeScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherCommsShell(theme: theme) { DispatcherCommsBody(kind: .responseTime) } }
}
struct DispatcherCommsSLAScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherCommsShell(theme: theme) { DispatcherCommsBody(kind: .slaCompliance) } }
}
struct DispatcherCommsEscalationScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherCommsShell(theme: theme) { DispatcherCommsBody(kind: .escalationFree) } }
}
struct DispatcherCommsClosureScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherCommsShell(theme: theme) { DispatcherCommsBody(kind: .threadClosure) } }
}
struct DispatcherCommsVolumeScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherCommsShell(theme: theme) { DispatcherCommsBody(kind: .threadVolume) } }
}
struct DispatcherCommsFTRScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherCommsShell(theme: theme) { DispatcherCommsBody(kind: .firstTouchResolution) } }
}
struct DispatcherCommsQuarterScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherCommsShell(theme: theme) { DispatcherCommsBody(kind: .quarter) } }
}

// MARK: - Previews

#Preview("480 Review · Dark")     { DispatcherCommsReviewScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("481 Resp · Light")      { DispatcherCommsResponseTimeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("482 SLA · Dark")        { DispatcherCommsSLAScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("483 Escal · Light")     { DispatcherCommsEscalationScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("484 Closure · Dark")    { DispatcherCommsClosureScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("485 Volume · Light")    { DispatcherCommsVolumeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("486 FTR · Dark")        { DispatcherCommsFTRScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("487 Quarter · Light")   { DispatcherCommsQuarterScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
