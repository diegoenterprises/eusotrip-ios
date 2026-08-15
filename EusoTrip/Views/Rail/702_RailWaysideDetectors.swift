//
//  702_RailWaysideDetectors.swift
//  EusoTrip — Rail Engineer · Wayside Detector Reads (mechanical-integrity
//  threshold board: WILD impact-load + HBD hot-bearing + DED dragging-equipment).
//
//  Bespoke port of "05 Rail/Light-SVG/702 Rail Wayside Detector Reads.svg" (+ Dark).
//  ARCHETYPE = THRESHOLD-BAR TREND BOARD — alarm-verdict hero (worst read),
//  per-site detector list with threshold bars + NORMAL/ALARM verdicts.
//  Distinct from the AEI identity read-trail; 702 is mechanical integrity.
//
//  Role: RAIL_ENGINEER (carrier family). transportMode=rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getRailInspections  EXISTS:1915 {limit} →
//        [{id,type,date,location,status,inspector,notes,passed}]. Wayside
//        reads persist as rail_inspections rows of type "wayside_detector"
//        per the design contract — this screen filters to that type and
//        renders ONLY what is on file.
//

import SwiftUI

struct RailWaysideDetectorsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            RailWaysideDetectorsBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct InspectionRow702: Decodable {
    let id: String?
    let type: String?
    let date: String?
    let location: String?
    let status: String?
    let inspector: String?
    let notes: String?
    let passed: Bool?

    var rowKey: String { id ?? "\(date ?? "")-\(location ?? "")" }
}

private struct LimitInput702: Encodable { let limit: Int }

/// One rendered detector read. `reading`/`limit` are present only when the
/// real notes text carries a parseable value — never synthesized.
private struct DetectorRead702: Identifiable {
    let key: String
    let location: String
    let detectorType: String
    let date: Date?
    let verdict: Verdict
    let readingText: String?
    let readingValue: Double?
    let limitValue: Double?
    let notes: String?

    var id: String { key }

    enum Verdict { case normal, review, alarm
        var label: String { switch self { case .normal: "NORMAL"; case .review: "REVIEW"; case .alarm: "ALARM" } }
        var color: Color { switch self { case .normal: Brand.success; case .review: Brand.warning; case .alarm: Brand.danger } }
    }
}

/// One real trackside read off `railMechanical.getWaysideDetectorReads`.
private struct WaysideReadRow702: Decodable, Identifiable {
    let id: String
    let trainId: String?
    let railcarNumber: String?
    let site: String?
    let milepost: String?
    let detectorType: String?
    let reading: Double?
    let threshold: Double?
    let unit: String?
    let alarm: Bool?
    let readAt: String?
}
private struct WaysideInput702: Encodable { let limit: Int }

// MARK: - Body

private struct RailWaysideDetectorsBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [InspectionRow702] = []
    @State private var waysideReads: [WaysideReadRow702] = []
    @State private var loading = true
    @State private var regime = 0
    @State private var isFlagging = false
    @State private var flagMessage: String? = nil

    private let regimes: [(String, String)] = [("US · AAR", "S-918 / FRA"),
                                               ("CA · TC", "Wayside Std"),
                                               ("MX · ARTF", "Detector")]

    /// Real wayside reads. When the dedicated detector feed has rows they are
    /// the true source; otherwise fall back to wayside-tagged inspections.
    private var reads: [DetectorRead702] {
        if !waysideReads.isEmpty {
            return waysideReads.map { w in
                let verdict: DetectorRead702.Verdict = {
                    if w.alarm == true { return .alarm }
                    if let r = w.reading, let t = w.threshold, t > 0, r >= t * 0.9 { return .review }
                    return .normal
                }()
                let loc = [w.site, w.milepost.map { "MP \($0)" }].compactMap { $0 }.joined(separator: " · ")
                let readingText: String? = w.reading.map { r in "\(String(format: "%.1f", r))\(w.unit.map { " \($0)" } ?? "")" }
                return DetectorRead702(
                    key: w.id,
                    location: loc.isEmpty ? (w.trainId.map { "Train \($0)" } ?? "Location not recorded") : loc,
                    detectorType: w.detectorType ?? "WILD",
                    date: Self.date(w.readAt),
                    verdict: verdict,
                    readingText: readingText,
                    readingValue: w.reading,
                    limitValue: w.threshold,
                    notes: w.railcarNumber.map { "Railcar \($0)" }
                )
            }
        }
        return rows.compactMap { r -> DetectorRead702? in
            guard let t = r.type?.lowercased(), t.contains("wayside") else { return nil }
            let verdict: DetectorRead702.Verdict = {
                switch r.passed {
                case .some(true):  return .normal
                case .some(false): return .alarm
                case .none:        return .review
                }
            }()
            let (value, text, limit) = Self.parseReading(r.notes)
            return DetectorRead702(
                key: r.rowKey,
                location: r.location ?? "Location not recorded",
                detectorType: Self.detectorKind(r.type, notes: r.notes),
                date: Self.date(r.date),
                verdict: verdict,
                readingText: text,
                readingValue: value,
                limitValue: limit,
                notes: r.notes
            )
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private var alarms: [DetectorRead702] { reads.filter { $0.verdict == .alarm } }
    private var reviews: [DetectorRead702] { reads.filter { $0.verdict == .review } }
    private var worstAlarm: DetectorRead702? { alarms.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Wayside detectors")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text(reads.isEmpty ? "Impact load · hot bearing · dragging equipment"
                               : "\(reads.count) detector read\(reads.count == 1 ? "" : "s") on file")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else if reads.isEmpty {
                    EusoEmptyState(systemImage: "dot.radiowaves.left.and.right",
                                   title: "No detector reads on file",
                                   subtitle: "Impact-load, hot-bearing, and dragging-equipment reads appear as wayside inspections are recorded against railcars on this route.")
                } else {
                    verdictHero
                    listHeader
                    detectorList
                    triBand
                    footerActions
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .eusoRefreshable { await reload() }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            EusoTripEyebrow(verbatim: "CARRIER · RAIL · WAYSIDE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("DETECTOR FEED")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip(alarms.isEmpty ? "no alarms" : "\(alarms.count) alarm\(alarms.count == 1 ? "" : "s")",
                 alarms.isEmpty ? Brand.success : Brand.danger)
            chip(reviews.isEmpty ? "0 in review" : "\(reviews.count) in review", Brand.warning)
            chip("\(reads.count) reads", Brand.blue)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Verdict hero — the worst failed read when one exists; otherwise
    // an all-clear keyed to the real read set.

    private var verdictHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(worstAlarm != nil
                     ? "WAYSIDE INTEGRITY · ALARM · STOP & INSPECT"
                     : "WAYSIDE INTEGRITY · ALL READS WITHIN LIMITS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(worstAlarm != nil ? Brand.danger : Brand.success)
                Spacer()
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(worstAlarm != nil
                        ? LinearGradient(colors: [Brand.danger.opacity(0.14), Brand.warning.opacity(0.10)],
                                         startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [Brand.success.opacity(0.12), Brand.blue.opacity(0.08)],
                                         startPoint: .leading, endPoint: .trailing))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(worstAlarm?.readingText ?? (worstAlarm != nil ? "Alarmed" : "\(reads.count)"))
                            .font(.system(size: 30, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text(worstAlarm != nil ? "worst read" : "reads clear")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Text(worstAlarm.map { "\($0.location) · \($0.detectorType)" }
                         ?? "no detector alarm on file")
                        .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("LIMIT").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
                    Text(worstAlarm?.limitValue.map { Self.trim($0) } ?? "—")
                        .font(.system(size: 16, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(Brand.warning)
                    Text(worstAlarm?.limitValue == nil ? "not recorded" : "recorded")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var listHeader: some View {
        HStack {
            Text("DETECTOR READS · NEWEST FIRST")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("WILD / HBD / DED")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var detectorList: some View {
        VStack(spacing: 0) {
            ForEach(Array(reads.enumerated()), id: \.element.id) { i, d in
                detectorRow(d)
                if i < reads.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(.horizontal, 16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func detectorRow(_ d: DetectorRead702) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.location)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text(d.date.map { Self.shortLabel($0) } ?? "date not recorded")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
                Text(d.detectorType)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(Brand.blue)
                    .padding(.horizontal, 8).frame(height: 16)
                    .background(Capsule().fill(Brand.blue.opacity(0.12)))
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(d.readingText ?? "no numeric read")
                        .font(.system(size: d.readingText == nil ? 10 : 13,
                                      weight: d.readingText == nil ? .bold : .heavy))
                        .monospacedDigit()
                        .foregroundStyle(d.readingText == nil ? palette.textTertiary : palette.textPrimary)
                    Text(d.verdict.label)
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(d.verdict.color)
                }
            }
            // Threshold bar renders ONLY when both a real reading and a real
            // limit were recorded — never a synthesized fill.
            if let v = d.readingValue, let lim = d.limitValue, lim > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.bgCardSoft).frame(height: 8)
                        Capsule().fill(d.verdict.color)
                            .frame(width: geo.size.width * CGFloat(min(v / (lim * 1.15), 1.0)), height: 8)
                        Rectangle().fill(palette.textTertiary)
                            .frame(width: 1.6, height: 16)
                            .offset(x: geo.size.width * CGFloat(min(1.0 / 1.15, 1.0)))
                    }
                }
                .frame(height: 16)
            }
        }
        .padding(.vertical, 10)
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
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == regime ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { regime = i }
            }
        }
    }

    private var footerActions: some View {
        VStack(spacing: Space.s2) {
            if let m = flagMessage {
                Text(m).font(EType.caption).foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: Space.s3) {
                CTAButton(title: isFlagging ? "Flagging…" : "Flag bad-order", action: { Task { await flagDetector() } })
                    .frame(maxWidth: .infinity)
                    .disabled(isFlagging || alarms.isEmpty)
                Button(action: { Task { await reload() } }) {
                Text("Refresh feed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132)
                    .frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Load + parsing

    private func reload() async {
        loading = true
        async let inspResult: [InspectionRow702]? = try? await EusoTripAPI.shared.query(
            "railShipments.getRailInspections", input: LimitInput702(limit: 200))
        async let waysideResult: [WaysideReadRow702]? = try? await EusoTripAPI.shared.query(
            "railMechanical.getWaysideDetectorReads", input: WaysideInput702(limit: 200))
        self.rows = (await inspResult) ?? []
        self.waysideReads = (await waysideResult) ?? []
        loading = false
    }

    private func flagDetector() async {
        guard let w = worstAlarm else { return }
        guard !isFlagging else { return }
        isFlagging = true; defer { isFlagging = false }
        let idVal = Int(w.key.replacingOccurrences(of: "wsr_", with: "")) ?? 0
        guard idVal > 0 else {
            flagMessage = "Can't flag synthetic inspection row."
            return
        }
        struct In: Encodable { let readId: Int; let alarm: Bool }
        struct Out: Decodable { let success: Bool }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "railMechanical.flagDetectorAlarm",
                input: In(readId: idVal, alarm: true))
            flagMessage = "Alarm flagged successfully."
            await reload()
        } catch {
            flagMessage = "Flagging failed. Check your connection."
        }
    }

    /// Detector class from the recorded type/notes: WILD (impact), HBD
    /// (hot bearing), DED (dragging equipment). Defaults to the recorded
    /// type text when no class keyword is present.
    private static func detectorKind(_ type: String?, notes: String?) -> String {
        let hay = "\(type ?? "") \(notes ?? "")".lowercased()
        if hay.contains("wild") || hay.contains("impact") { return "WILD" }
        if hay.contains("hbd") || hay.contains("bearing") || hay.contains("hot box") { return "HBD" }
        if hay.contains("ded") || hay.contains("dragging") { return "DED" }
        return "WAYSIDE"
    }

    /// Best-effort numeric parse from the real notes text, e.g.
    /// "92 kip" / "168 F" / "limit 90". Returns (reading, readingText, limit).
    private static func parseReading(_ notes: String?) -> (Double?, String?, Double?) {
        guard let notes, !notes.isEmpty else { return (nil, nil, nil) }
        var reading: Double? = nil
        var readingText: String? = nil
        var limit: Double? = nil

        let ns = notes as NSString
        if let rx = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*(kip|kips|°?f|°?c|lbs?)"#,
                                             options: [.caseInsensitive]),
           let m = rx.firstMatch(in: notes, range: NSRange(location: 0, length: ns.length)) {
            let numStr = ns.substring(with: m.range(at: 1))
            let unit = ns.substring(with: m.range(at: 2))
            reading = Double(numStr)
            readingText = "\(numStr) \(unit)"
        }
        if let rx = try? NSRegularExpression(pattern: #"limit\s*[:=]?\s*(\d+(?:\.\d+)?)"#,
                                             options: [.caseInsensitive]),
           let m = rx.firstMatch(in: notes, range: NSRange(location: 0, length: ns.length)) {
            limit = Double(ns.substring(with: m.range(at: 1)))
        }
        return (reading, readingText, limit)
    }

    private static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }

    private static func shortLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d · HH:mm"
        return f.string(from: d)
    }

    private static func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

#Preview("702 · Rail Wayside Detectors · Night") {
    RailWaysideDetectorsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("702 · Rail Wayside Detectors · Light") {
    RailWaysideDetectorsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
