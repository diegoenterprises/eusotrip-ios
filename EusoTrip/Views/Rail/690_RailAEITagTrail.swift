//
//  690_RailAEITagTrail.swift
//  EusoTrip — Rail Engineer · AEI Tag Trail (S-918B tag-swap detection).
//
//  Bespoke port of "05 Rail/Dark-SVG/690 Rail AEI Tag Trail.svg".
//  ARCHETYPE = FRAUD TIMELINE — a tag-integrity verdict hero (suspect-read
//  count, where the mark diverged) over a vertical RFID read trail down the
//  line: each node is one reader site with its timestamp, decoded AEI mark,
//  and a match/suspect verdict, the suspect node danger-washed. Deliberately
//  NOT 706's fleet delta matrix, NOT 708's uniqueness ledger, NOT a list.
//
//  Role: RAIL_ENGINEER (carrier/compliance). transportMode=rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railGate.ts +
//  aei.ts + railTrust.ts):
//    railGate.getGateActivity  EXISTS railGate.ts:102 {windowHours, railcarNumber,
//        limit} → {events:[{railcarNumber,site,gateType,aeiTag,sealNumber,
//        anomaly,anomalyReason,occurredAt}], counts, avgTurnMinutes}. This is
//        the REAL AEI-tag read trail — every gate event carries the tag decoded
//        at that reader (rail_gate_events.aeiTag) and an anomaly flag. The read
//        trail below is those rows, newest at the bottom; a node is SUSPECT the
//        moment its event.anomaly fires (mark ≠ record).
//    aei.flagTagSwap  EXISTS aei.ts:19 {railcarNumber} → writes an auditLogs
//        flag_tag_swap row. The primary CTA fires this after confirmation.
//    railTrust.flagSuspectCar EXISTS railTrust.ts:27 — the broader suspect-car
//        flag; not fired here (tag-swap is the specific signal).
//  VERIFIED ABSENT (honest state, never fabricated):
//    A dedicated aei.getReadTrail with decoded-mark-vs-waybill delta + RSSI is
//    not on disk; the trail binds to the real gate-reader AEI events instead,
//    and RSSI is shown as the reader's gate type (the real column), never an
//    invented dBm. An empty feed renders an honest empty state, never a read.
//

import SwiftUI

struct RailAEITagTrailScreen: View {
    let theme: Theme.Palette
    /// The car whose reader trail is under review. Real gate events are pulled
    /// for this mark, tenant-scoped server-side.
    var railcarNumber: String = "GATX 215704"

    var body: some View {
        Shell(theme: theme) {
            RailAEITagTrailBody(railcarNumber: railcarNumber)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror railGate.getGateActivity)

private struct GateActivity690: Decodable {
    struct Ev: Decodable, Identifiable {
        let id: String?
        let railcarNumber: String?
        let trainId: String?
        let gateType: String?
        let site: String?
        let sealNumber: String?
        let aeiTag: String?
        let anomaly: Bool?
        let anomalyReason: String?
        let occurredAt: String?
        var rowId: String { id ?? UUID().uuidString }
    }
    struct Counts: Decodable {
        let gateIn: Int?; let gateOut: Int?; let flags: Int?; let anomalies: Int?
    }
    let events: [Ev]?
    let counts: Counts?
    let avgTurnMinutes: Int?
}

private struct GateInput690: Encodable {
    let windowHours: Int
    let railcarNumber: String
    let limit: Int
}

// MARK: - Body

private struct RailAEITagTrailBody: View {
    let railcarNumber: String

    @Environment(\.palette) private var palette
    @State private var events: [GateActivity690.Ev] = []
    @State private var suspectCount = 0
    @State private var loading = true
    @State private var flagging = false
    @State private var flagLanded = false
    @State private var flagError: String? = nil
    @State private var dismissed = false
    @State private var regime = 0
    @State private var showFlagConfirm = false

    private let regimes: [(String, String)] = [("US · AAR", "Railinc CIF"),
                                               ("CA · TC",  "Railinc CIF"),
                                               ("MX · ARTF", "SIID")]

    /// Chronological trail — oldest reader at the top, newest at the bottom,
    /// so the eye follows the car down the line to the suspect node.
    private var trail: [GateActivity690.Ev] {
        events.sorted { ($0.occurredAt ?? "") < ($1.occurredAt ?? "") }
    }

    private var firstSuspect: GateActivity690.Ev? { trail.first { $0.anomaly == true } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("AEI tag trail")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("RFID reads · car \(railcarNumber)")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else {
                    verdictHero
                    trailHeader
                    readTrail
                    triBand
                    footerActions
                    if let err = flagError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    }
                    if flagLanded {
                        LifecycleCard {
                            Text("Tag-swap flag recorded — car \(railcarNumber) is now in the fraud queue for review.")
                                .font(EType.caption).foregroundStyle(Brand.success)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .eusoRefreshable { await reload() }
        .confirmationDialog("Flag this car for a tag swap?", isPresented: $showFlagConfirm, titleVisibility: .visible) {
            Button("Flag tag swap", role: .destructive) { Task { await flag() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Car \(railcarNumber) enters the fraud-review queue. Use this only when a decoded mark diverges from the record.")
        }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            EusoTripEyebrow(verbatim: "CARRIER · RAIL · TAG INTEGRITY")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("AEI · S-918B")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip("\(trail.count) read\(trail.count == 1 ? "" : "s")", palette.textSecondary)
            chip("\(suspectCount) suspect", suspectCount > 0 ? Brand.danger : Brand.success)
            chip(regimes[regime].1.lowercased(), Brand.blue)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Verdict hero — the integrity call, danger-washed when a mark diverged.

    private var verdictHero: some View {
        let hasSuspect = suspectCount > 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(hasSuspect ? "AEI TAG INTEGRITY · \(suspectCount) SUSPECT READ\(suspectCount == 1 ? "" : "S")"
                                : "AEI TAG INTEGRITY · CLEAN TRAIL")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(hasSuspect ? Brand.danger : Brand.success)
                Spacer()
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [(hasSuspect ? Brand.danger : Brand.success).opacity(0.13), Brand.blue.opacity(0.06)],
                                       startPoint: .leading, endPoint: .trailing))
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill((hasSuspect ? Brand.danger : Brand.success).opacity(0.10)).frame(width: 48, height: 48)
                    Image(systemName: hasSuspect ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(hasSuspect ? Brand.danger : Brand.success)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(hasSuspect ? "Mark mismatch on the trail" : "Every reader agreed")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(heroDetail)
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(hasSuspect ? AnyShapeStyle(Brand.danger.opacity(0.55)) : AnyShapeStyle(LinearGradient.primary), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var heroDetail: String {
        if let s = firstSuspect {
            let mark = s.aeiTag ?? "unreadable mark"
            let site = s.site ?? "a reader"
            return "decoded \(mark) at \(site) — \(s.anomalyReason ?? "does not match the record")"
        }
        if trail.isEmpty { return "No AEI reads are on file for this car in the window. A verdict needs at least one decoded reader pass." }
        return "\(trail.count) readers decoded the same mark for \(railcarNumber). No tag swap on the trail."
    }

    private var trailHeader: some View {
        HStack {
            Text("RFID READ TRAIL · AEI S-918B")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("SITE · TIME · MARK")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Vertical read trail — a rail line the car travels down.

    @ViewBuilder
    private var readTrail: some View {
        if trail.isEmpty {
            EusoEmptyState(systemImage: "dot.radiowaves.up.forward",
                           title: "No reader passes on file",
                           subtitle: "No AEI gate reads are recorded for \(railcarNumber) in the last 30 days. The trail fills as the car passes each instrumented reader.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(trail.enumerated()), id: \.element.rowId) { i, ev in
                    trailNode(ev, isLast: i == trail.count - 1)
                }
            }
            .padding(16)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func trailNode(_ ev: GateActivity690.Ev, isLast: Bool) -> some View {
        let suspect = ev.anomaly == true
        let tone: Color = suspect ? Brand.danger : Brand.success
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().strokeBorder(tone, lineWidth: 2).frame(width: 20, height: 20)
                    Image(systemName: suspect ? "exclamationmark" : "checkmark")
                        .font(.system(size: 9, weight: .black)).foregroundStyle(tone)
                }
                if !isLast {
                    Rectangle().fill(palette.borderFaint).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(ev.site ?? readerLabel(ev.gateType))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(relTime(ev.occurredAt))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
                Text(ev.aeiTag ?? "mark not decoded")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(suspect ? Brand.danger : palette.textSecondary)
                Text(suspect ? (ev.anomalyReason ?? "mark diverged from record") : "\(readerLabel(ev.gateType)) · mark matches")
                    .font(.system(size: 9))
                    .foregroundStyle(suspect ? Brand.danger : palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
        .padding(.vertical, suspect ? 8 : 0)
        .padding(.horizontal, suspect ? 8 : 0)
        .background(suspect ? Brand.danger.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: suspect ? 10 : 0, style: .continuous))
    }

    private func readerLabel(_ gateType: String?) -> String {
        switch gateType {
        case "gate_in":  return "Gate-in reader"
        case "gate_out": return "Gate-out reader"
        case "flag":     return "Manual flag"
        default:         return "Wayside reader"
        }
    }

    private var triBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == regime ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == regime ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { regime = i }
            }
        }
    }

    @ViewBuilder
    private var footerActions: some View {
        if !dismissed {
            HStack(spacing: Space.s3) {
                CTAButton(title: flagging ? "Flagging…" : "Flag tag swap",
                          action: { if !flagging { showFlagConfirm = true } })
                    .frame(maxWidth: .infinity)
                    .disabled(flagging || suspectCount == 0)
                Button(action: { dismissed = true }) {
                    Text("Dismiss")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 118)
                        .frame(minHeight: 48, maxHeight: 48)
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                    .strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        } else {
            Text(suspectCount == 0 ? "Trail clean — nothing to flag." : "Dismissed. The suspect read stays on the audit record.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Load + flag

    private func reload() async {
        loading = true
        let g: GateActivity690? = try? await EusoTripAPI.shared.query(
            "railGate.getGateActivity",
            input: GateInput690(windowHours: 720, railcarNumber: railcarNumber, limit: 200))
        self.events = g?.events ?? []
        self.suspectCount = g?.counts?.anomalies ?? events.filter { $0.anomaly == true }.count
        loading = false
    }

    private func flag() async {
        flagging = true; flagError = nil; flagLanded = false
        struct In: Encodable { let railcarNumber: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("aei.flagTagSwap", input: In(railcarNumber: railcarNumber))
            flagLanded = true
        } catch {
            flagError = "The flag didn't record. The trail above is unchanged — check your connection and try again."
        }
        flagging = false
    }

    private func relTime(_ iso: String?) -> String {
        guard let iso, let d = Self.parseISO(iso) else { return "—" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        let g = ISO8601DateFormatter(); g.formatOptions = [.withInternetDateTime]
        return g.date(from: s)
    }
}

#Preview("690 · Rail AEI Tag Trail · Night") {
    RailAEITagTrailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("690 · Rail AEI Tag Trail · Light") {
    RailAEITagTrailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
