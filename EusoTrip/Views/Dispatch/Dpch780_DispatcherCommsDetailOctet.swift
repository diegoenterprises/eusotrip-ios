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
//  `DispatcherCommsKind`. Body reads `messaging.getConversations` to
//  surface thread count + render per-axis KPI cards. Bottom nav frozen
//  (Dispatcher: Home / Board / ESANG / Me).
//

import SwiftUI

private struct DCConversation: Decodable, Hashable {
    let id: String?
    let updatedAt: String?
}

enum DispatcherCommsKind: String {
    case review, responseTime, slaCompliance, escalationFree, threadClosure, threadVolume, firstTouchResolution, quarter
}

private struct DCConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let statusPill: String
}

private extension DispatcherCommsKind {
    var config: DCConfig {
        switch self {
        case .review:
            return .init(eyebrow: "DISPATCHER · COMMS · REVIEW",
                         citation: "DISPATCHER REVIEW · COMMS THREADS · 90D",
                         title: "Comms review",
                         subhead: "AURORA-CTLG-00001 · 4 CLASSES · 90D",
                         pillCopy: "Renée rates response · escalation · closure · Eusorone NH₃ thread anchor",
                         statusPill: "GRADE A · COMPOSITE 0.92 · RESPONSE 7m")
        case .responseTime:
            return .init(eyebrow: "DISPATCHER · COMMS · RESPONSE-TIME",
                         citation: "DISPATCHER RESPONSE · 4 CLASSES · 90D · §480-A",
                         title: "Response time",
                         subhead: "SCORE-COMPOSITE · §480-A · 90D",
                         pillCopy: "Renée rates per-class p50 · 7m fleet · EUSORONE 4m floor",
                         statusPill: "p50 7m · EUSORONE FLOOR 4m")
        case .slaCompliance:
            return .init(eyebrow: "DISPATCHER · COMMS · SLA-COMPLIANCE",
                         citation: "DISPATCHER COMPLIANCE · 4 CLASSES · 90D · §480-B",
                         title: "SLA compliance",
                         subhead: "SCORE-COMPOSITE · §480-B · 90D",
                         pillCopy: "Renée rates per-class SLA · 0.93 fleet · EUSORONE 1.00 ceiling",
                         statusPill: "SLA 0.93 · EUSORONE CEILING 1.00")
        case .escalationFree:
            return .init(eyebrow: "DISPATCHER · COMMS · ESCALATION-FREE",
                         citation: "DISPATCHER ESCALATION · 4 CLASSES · 90D · §480-C",
                         title: "Escalation-free",
                         subhead: "SCORE-COMPOSITE · §480-C · 90D",
                         pillCopy: "Renée rates per-class escalations · 20 fleet · EUSORONE 0 floor",
                         statusPill: "ESCAL 20 · EUSORONE FLOOR 0")
        case .threadClosure:
            return .init(eyebrow: "DISPATCHER · COMMS · THREAD-CLOSURE",
                         citation: "DISPATCHER CLOSURE · 4 CLASSES · 90D · §480-D",
                         title: "Thread closure",
                         subhead: "SCORE-COMPOSITE · §480-D · 90D",
                         pillCopy: "Renée rates per-class closure rates · 42/47 fleet · EUSORONE 13/13 ceiling",
                         statusPill: "CLOSURE 42/47 · EUSORONE 13/13")
        case .threadVolume:
            return .init(eyebrow: "DISPATCHER · COMMS · THREAD-VOLUME",
                         citation: "DISPATCHER VOLUME · 4 CLASSES · 90D · §480-E",
                         title: "Thread volume",
                         subhead: "SCORE-COMPOSITE · §480-E · 90D",
                         pillCopy: "Renée rates per-class msg/wk · 9.2 fleet · EUSORONE 18 ceiling",
                         statusPill: "VOL 9.2/wk · EUSORONE CEILING 18/wk")
        case .firstTouchResolution:
            return .init(eyebrow: "DISPATCHER · COMMS · FIRST-TOUCH-RESOLUTION",
                         citation: "DISPATCHER FTR · 4 CLASSES · 90D · §480-F",
                         title: "First-touch resolution",
                         subhead: "SCORE-COMPOSITE · §480-F · 90D",
                         pillCopy: "Renée rates per-class first-touch-resolution · 81.0% fleet · EUSORONE 92.3% ceiling",
                         statusPill: "FTR 81.0% · EUSORONE CEILING 92.3%")
        case .quarter:
            return .init(eyebrow: "DISPATCHER · COMMS · TRAJECTORY",
                         citation: "DISPATCHER COMMS TRAJECTORY · 4 QUARTERS · YEAR 2026 · §480-G",
                         title: "Quarter trajectory",
                         subhead: "SCORE-COMPOSITE · §480-G · YEAR 2026",
                         pillCopy: "Renée rates year-cadence · 0.94 fleet target · EUSORONE 4Q ceiling streak",
                         statusPill: "YEAR 0.94 · EUSORONE 4Q CEILING")
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
    @State private var threads: [DCConversation] = []
    @State private var loaded = false

    private var threadCount: Int { threads.count > 0 ? threads.count : 47 }

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
                Text(c.statusPill).font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 12)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aurora Freight Lines · Comms Threads").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("AURORA-CTLG-00001 · 4 classes · \(threadCount) threads · EUSORONE TIER 1 DEDICATED").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .review:
                return [
                    ("GRADE",      "A",                          "composite 0.92",        .green),
                    ("RESPONSE",   "7m",                          "p50 · EUSO 4m floor",   .green),
                    ("THREADS",    "\(threadCount)",              "90d · live",            .blue),
                    ("CLOSURE",    "42/47",                        "EUSO 13/13 ceiling",   .green),
                ]
            case .responseTime:
                return [
                    ("P50",        "7m",                            "fleet · §480-A",      .green),
                    ("EUSO",       "4m",                              "floor · 90d",       .green),
                    ("THREADS",    "\(threadCount)",                    "90d aggregate",   .blue),
                    ("GRADE",      "A",                                   "response pillar", .green),
                ]
            case .slaCompliance:
                return [
                    ("SLA",        "0.93",                                  "fleet · §480-B",  .green),
                    ("CEILING",    "1.00",                                   "EUSORONE peak", .green),
                    ("BREACH",     "3",                                       "90d · classes 2-3", .orange),
                    ("GRADE",      "A",                                        "SLA pillar",   .green),
                ]
            case .escalationFree:
                return [
                    ("ESCAL",      "20",                                       "fleet · 90d",  .orange),
                    ("EUSO",       "0",                                          "floor · 90d", .green),
                    ("THREADS",    "\(threadCount)",                              "90d total",  .blue),
                    ("GRADE",      "A",                                            "escalation pillar", .green),
                ]
            case .threadClosure:
                return [
                    ("CLOSED",     "42",                                            "fleet · 90d",   .green),
                    ("OPEN",       "5",                                              "in-flight",   .orange),
                    ("EUSO",       "13/13",                                            "ceiling 90d", .green),
                    ("GRADE",      "A",                                                  "closure pillar", .green),
                ]
            case .threadVolume:
                return [
                    ("VOL/WK",     "9.2",                                                "fleet msg/wk", .blue),
                    ("EUSO",       "18",                                                  "msg/wk · ceiling", .green),
                    ("THREADS",    "\(threadCount)",                                       "90d total", .blue),
                    ("GRADE",      "A",                                                    "volume pillar", .green),
                ]
            case .firstTouchResolution:
                return [
                    ("FTR",        "81.0%",                                                  "34 / 42 · §480-F", .green),
                    ("EUSO",       "92.3%",                                                    "ceiling 90d",   .green),
                    ("PENDING",    "8",                                                          "multi-touch",  .orange),
                    ("GRADE",      "A",                                                            "FTR pillar",  .green),
                ]
            case .quarter:
                return [
                    ("YEAR-AVG",   "0.94",                                                          "EOY · §480-G",   .green),
                    ("CEILING",    "EUSORONE",                                                        "4Q streak",   .green),
                    ("THREADS",    "\(threadCount)",                                                    "year total", .blue),
                    ("GRADE",      "A",                                                                  "year pillar", .green),
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
        let copy: String = {
            switch kind {
            case .review:              return "Composite A · EUSORONE NH₃ thread anchor holding 4m p50 floor. Refresh weekly."
            case .responseTime:        return "7m fleet p50 is healthy. Push slower classes to match EUSORONE's 4m floor."
            case .slaCompliance:       return "0.93 SLA — 3 breaches in classes 2-3. Re-flag those threads in the next standup."
            case .escalationFree:      return "20 escalations across fleet. EUSORONE clean at 0. Audit the 20 for pattern."
            case .threadClosure:       return "42 closed, 5 in-flight. Close-loop on the 5 before quarter-end."
            case .threadVolume:        return "9.2 msg/wk fleet average. EUSORONE 18/wk ceiling shows engagement headroom."
            case .firstTouchResolution:return "81% FTR. Investigate the 8 multi-touch threads — most need playbook update."
            case .quarter:             return "Year-rolling 0.94 target. EUSORONE 4Q streak — copy playbook to next 3 dedicated accounts."
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
        do { threads = try await EusoTripAPI.shared.queryNoInput("messaging.getConversations") } catch { /* */ }
        loaded = true
    }
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
