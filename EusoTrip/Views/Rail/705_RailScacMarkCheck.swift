//
//  705_RailScacMarkCheck.swift
//  EusoTrip — Rail Engineer · SCAC Mark Check (carrier-mark spoof detection).
//
//  Bespoke port of "05 Rail/Light-SVG/705 Rail SCAC Mark Check.svg" (+ Dark).
//  ARCHETYPE = STRING-SIMILARITY ADJUDICATOR — two-plate compare hero
//  (entered mark vs nearest registered mark with an edit-distance badge)
//  over a ranked candidate list with Levenshtein distance + similarity bars.
//  Deliberately not 704's score gauge.
//
//  Role: RAIL_ENGINEER (carrier/compliance). transportMode=rail.
//
//  WIRING MANIFEST:
//    Mark entry + Levenshtein adjudication run ON-DEVICE against a bundled
//    reference set of REAL registered reporting marks (Class I carriers +
//    major car owners/lessors). The computation is real; the coverage is
//    honestly labeled as a reference set, not the full mark directory.
//  VERIFIED ABSENT (honest state, never fabricated):
//    railinc.cifMarkCheck({mark}) — no full industry mark-directory lookup
//    exists on disk (SCAC strings appear in integration payloads but no
//    registry). The candidate list is therefore scoped to the bundled
//    reference set and says so.
//    railTrust.rejectMark (irreversible) — absent; the Reject CTA surfaces
//    the honest state instead of a fake rejection receipt.
//    fraudGuard SCAC-variant signal — the verdict here does not yet feed the
//    704 score; the two screens read independently.
//

import SwiftUI

struct RailScacMarkCheckScreen: View {
    let theme: Theme.Palette
    /// Mark under adjudication — pre-filled when opened from a tender.
    var enteredMark: String = ""

    var body: some View {
        Shell(theme: theme) {
            RailScacMarkCheckBody(initialMark: enteredMark)
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

// MARK: - Reference set — REAL registered reporting marks (Class I + major
// car owners/lessors). Reference data, not a directory claim; the screen
// labels the coverage honestly.

private struct RegisteredMark705: Identifiable {
    let mark: String
    let owner: String
    let classLabel: String
    var id: String { mark }

    static let referenceSet: [RegisteredMark705] = [
        .init(mark: "BNSF", owner: "BNSF Railway",                    classLabel: "Class I"),
        .init(mark: "UP",   owner: "Union Pacific",                   classLabel: "Class I"),
        .init(mark: "CSXT", owner: "CSX Transportation",              classLabel: "Class I"),
        .init(mark: "NS",   owner: "Norfolk Southern",                classLabel: "Class I"),
        .init(mark: "CN",   owner: "Canadian National",               classLabel: "Class I"),
        .init(mark: "CPKC", owner: "Canadian Pacific Kansas City",    classLabel: "Class I"),
        .init(mark: "KCS",  owner: "Kansas City Southern",            classLabel: "Class I heritage"),
        .init(mark: "KCSM", owner: "Kansas City Southern de México",  classLabel: "Mexico"),
        .init(mark: "FXE",  owner: "Ferromex",                        classLabel: "Mexico"),
        .init(mark: "AMTK", owner: "Amtrak",                          classLabel: "Passenger"),
        .init(mark: "DTTX", owner: "TTX Company · doublestack",       classLabel: "Car owner"),
        .init(mark: "TTGX", owner: "TTX Company · autorack",          classLabel: "Car owner"),
        .init(mark: "GATX", owner: "GATX Corporation",                classLabel: "Lessor"),
        .init(mark: "TILX", owner: "Trinity Industries Leasing",      classLabel: "Lessor"),
        .init(mark: "UTLX", owner: "Union Tank Car",                  classLabel: "Lessor"),
        .init(mark: "PROX", owner: "Procor",                          classLabel: "Lessor"),
        .init(mark: "SHPX", owner: "American Railcar Leasing",        classLabel: "Lessor"),
        .init(mark: "GBRX", owner: "Greenbrier Leasing",              classLabel: "Lessor"),
    ]
}

private struct Candidate705: Identifiable {
    let registered: RegisteredMark705
    let distance: Int
    let similarity: Double
    var id: String { registered.mark }
}

// MARK: - Body

private struct RailScacMarkCheckBody: View {
    let initialMark: String

    @Environment(\.palette) private var palette
    @State private var entered = ""
    @State private var regime = 0
    @State private var showRejectNotice = false
    @State private var showOverrideNotice = false
    /// Live directory verdict off railMechanical.cifMarkCheck (exact/near/unknown).
    @State private var serverVerdict: String? = nil
    @State private var serverMatchOwner: String? = nil

    private struct CifMarkInput705: Encodable { let mark: String }
    private struct CifMarkResult705: Decodable {
        struct Match: Decodable { let mark: String?; let name: String? }
        let mark: String?; let verdict: String?; let match: Match?
    }

    private func checkLiveDirectory() async {
        let m = entered.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard m.count >= 1 else { serverVerdict = nil; serverMatchOwner = nil; return }
        if let r: CifMarkResult705 = try? await EusoTripAPI.shared.query(
            "railMechanical.cifMarkCheck", input: CifMarkInput705(mark: m)) {
            serverVerdict = r.verdict
            serverMatchOwner = r.match?.name
        }
    }

    private let regimes: [(String, String)] = [("US · AAR", "mark registry"),
                                               ("CA · TC", "mark registry"),
                                               ("MX · ARTF", "SIID registry")]

    private var cleanMark: String {
        entered.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// Real Levenshtein adjudication of the entered mark against every
    /// reference mark, nearest first.
    private var candidates: [Candidate705] {
        guard !cleanMark.isEmpty else { return [] }
        return RegisteredMark705.referenceSet
            .map { reg -> Candidate705 in
                let d = Self.levenshtein(cleanMark, reg.mark)
                let maxLen = max(cleanMark.count, reg.mark.count)
                let sim = maxLen == 0 ? 0 : 1.0 - Double(d) / Double(maxLen)
                return Candidate705(registered: reg, distance: d, similarity: max(sim, 0))
            }
            .sorted { $0.distance == $1.distance ? $0.similarity > $1.similarity : $0.distance < $1.distance }
    }

    private var nearest: Candidate705? { candidates.first }

    /// Exact hit = the mark IS registered in the reference set.
    private var exactHit: Candidate705? { candidates.first { $0.distance == 0 } }

    /// Lookalike = within edit distance 2 of a registered mark without
    /// being that mark.
    private var lookalike: Candidate705? {
        guard exactHit == nil else { return nil }
        return candidates.first { $0.distance <= 2 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("SCAC mark check")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text(cleanMark.isEmpty ? "Measure a tendered mark against registered reporting marks"
                                   : "mark \(cleanMark) · \(RegisteredMark705.referenceSet.count) reference marks")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                markEntry
                if cleanMark.isEmpty {
                    EusoEmptyState(systemImage: "textformat.abc",
                                   title: "Enter a reporting mark",
                                   subtitle: "Type the mark exactly as it appears on the tender. Edit distance to every reference mark computes as you type.")
                } else {
                    compareHero
                    candidatesHeader
                    candidateList
                }
                triBand
                if !cleanMark.isEmpty { footerActions }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .onAppear { if entered.isEmpty { entered = initialMark } }
        .task(id: entered) {
            // Debounce, then confirm the mark against the live CIF directory.
            try? await Task.sleep(nanoseconds: 350_000_000)
            await checkLiveDirectory()
        }
        .alert("Mark rejection can't be recorded", isPresented: $showRejectNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A mark rejection isn't recorded from this device. The adjudication above stands — hold the tender on the trust verdict screen so the mark is reviewed before the car is accepted.")
        }
        .alert("Override is an admin decision", isPresented: $showOverrideNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Accepting a lookalike mark is an audited admin decision, not one this screen can make. The similarity result above stays on record.")
        }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            Text("✦ CARRIER · RAIL · MARK CHECK")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("REFERENCE SET · \(RegisteredMark705.referenceSet.count)")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            if cleanMark.isEmpty {
                chip("awaiting mark", palette.textSecondary)
            } else if exactHit != nil {
                chip("registered", Brand.success)
                chip("exact match", Brand.success)
            } else if let l = lookalike {
                chip("\(l.distance) edit\(l.distance == 1 ? "" : "s") away", Brand.danger)
                chip("lookalike", Brand.danger)
            } else {
                chip("no near match", Brand.warning)
                chip("manual review", Brand.warning)
            }
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Mark entry — the real input driving the adjudication.

    private var markEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "textformat.abc").foregroundStyle(palette.textTertiary)
                TextField("Reporting mark, e.g. CSXT", text: $entered)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            if let v = serverVerdict {
                HStack(spacing: 6) {
                    Circle().fill(liveVerdictColor(v)).frame(width: 7, height: 7)
                    Text(liveVerdictLabel(v)).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    if let owner = serverMatchOwner { Text("· \(owner)").font(.system(size: 10)).foregroundStyle(palette.textTertiary).lineLimit(1) }
                }
            }
        }
    }

    private func liveVerdictColor(_ v: String) -> Color {
        switch v { case "exact": return Brand.success; case "near": return Brand.warning; default: return palette.textTertiary }
    }
    private func liveVerdictLabel(_ v: String) -> String {
        switch v {
        case "exact": return "LIVE DIRECTORY · REGISTERED MARK"
        case "near":  return "LIVE DIRECTORY · NO EXACT MATCH — LOOKALIKES EXIST"
        default:      return "LIVE DIRECTORY · MARK NOT FOUND"
        }
    }

    // MARK: Compare hero — entered vs nearest, edit-distance badge between.

    @ViewBuilder
    private var compareHero: some View {
        if let n = nearest {
            let danger = exactHit == nil && n.distance <= 2
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(exactHit != nil
                         ? "CARRIER MARK INTEGRITY · REGISTERED MARK"
                         : (danger ? "CARRIER MARK INTEGRITY · LOOKALIKE DETECTED"
                                   : "CARRIER MARK INTEGRITY · NO NEAR MATCH"))
                        .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(exactHit != nil ? Brand.success : (danger ? Brand.danger : Brand.warning))
                    Spacer()
                }
                .padding(.horizontal, 16).frame(height: 40)
                .background(LinearGradient(colors: [(exactHit != nil ? Brand.success : (danger ? Brand.danger : Brand.warning)).opacity(0.13),
                                                    Brand.warning.opacity(0.08)],
                                           startPoint: .leading, endPoint: .trailing))
                HStack(spacing: 8) {
                    plate("ENTERED ON TENDER", cleanMark, danger: danger)
                    ZStack {
                        Circle()
                            .strokeBorder(danger ? Brand.danger : palette.textTertiary, lineWidth: 1.6)
                            .frame(width: 34, height: 34)
                        VStack(spacing: 0) {
                            Text("\(n.distance)")
                                .font(.system(size: 14, weight: .heavy)).monospacedDigit()
                                .foregroundStyle(danger ? Brand.danger : palette.textSecondary)
                            Text("EDIT")
                                .font(.system(size: 6.5, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(danger ? Brand.danger : palette.textSecondary)
                        }
                    }
                    plate("NEAREST · REFERENCE SET", n.registered.mark, danger: false)
                }
                .padding(.horizontal, 14).padding(.top, 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verdictLine(n))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(verdictCaption(n))
                        .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 14)
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(LinearGradient.primary, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }

    private func verdictLine(_ n: Candidate705) -> String {
        if exactHit != nil { return "\(cleanMark) is a registered mark — \(n.registered.owner)." }
        if n.distance <= 2 { return "Lookalike to \(n.registered.owner) (\(n.registered.mark))." }
        return "\(cleanMark) is not near any mark in the reference set."
    }

    private func verdictCaption(_ n: Candidate705) -> String {
        if exactHit != nil { return "exact registry hit · no spoof pattern" }
        if n.distance <= 2 { return "within 2 edits of a registered mark — treat as a spoof until reviewed" }
        return "reference set covers Class I carriers + major car owners; a mark outside it needs manual review"
    }

    private func plate(_ label: String, _ mark: String, danger: Bool) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(danger ? Brand.danger : palette.textTertiary)
            Text(mark)
                .font(.system(size: 26, weight: .heavy, design: .monospaced))
                .foregroundStyle(danger ? Brand.danger : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity).frame(height: 58)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(danger ? Brand.danger.opacity(0.08) : palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(danger ? Brand.danger.opacity(0.55) : palette.borderFaint))
    }

    private var candidatesHeader: some View {
        HStack {
            Text("NEAREST REGISTERED MARKS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("reference set · not the full directory")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var candidateList: some View {
        VStack(spacing: 0) {
            let top = Array(candidates.prefix(5))
            ForEach(Array(top.enumerated()), id: \.element.id) { i, c in
                candidateRow(c)
                if i < top.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(.horizontal, 16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func candidateRow(_ c: Candidate705) -> some View {
        let near = c.distance <= 2 && exactHit == nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(c.registered.mark)
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(c.distance == 0 ? "exact" : "dist \(c.distance)")
                    .font(.system(size: 11, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(c.distance == 0 ? Brand.success : (near ? Brand.danger : Brand.success))
            }
            Text("\(c.registered.owner) · \(c.registered.classLabel)")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            HStack(spacing: 8) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.bgCardSoft).frame(height: 6)
                        Capsule().fill(near ? Brand.danger : Brand.success)
                            .frame(width: g.size.width * CGFloat(c.similarity), height: 6)
                    }
                }
                .frame(height: 6)
                Text("\(Int(c.similarity * 100))% match")
                    .font(.system(size: 9)).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, 12)
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
        HStack(spacing: Space.s3) {
            CTAButton(title: "Reject mark", action: { showRejectNotice = true })
                .frame(maxWidth: .infinity)
            Button(action: { showOverrideNotice = true }) {
                Text("Admin override")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 140)
                    .frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Levenshtein — real edit distance, small inputs so O(n·m) is fine.

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aa = Array(a), bb = Array(b)
        if aa.isEmpty { return bb.count }
        if bb.isEmpty { return aa.count }
        var prev = Array(0...bb.count)
        var cur = [Int](repeating: 0, count: bb.count + 1)
        for i in 1...aa.count {
            cur[0] = i
            for j in 1...bb.count {
                let cost = aa[i - 1] == bb[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[bb.count]
    }
}

#Preview("705 · Rail SCAC Mark Check · Night") {
    RailScacMarkCheckScreen(theme: Theme.dark, enteredMark: "CSXG").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("705 · Rail SCAC Mark Check · Light") {
    RailScacMarkCheckScreen(theme: Theme.light, enteredMark: "CSXG").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
