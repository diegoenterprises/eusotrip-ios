//
//  708_RailSealHashCheck.swift
//  EusoTrip — Rail Engineer · Seal Hash Check (CTPAT seal-spoof / reuse).
//
//  Bespoke port of "05 Rail/Dark-SVG/708 Rail Seal Hash Check.svg".
//  ARCHETYPE = HASH-UNIQUENESS LEDGER — a seal-hash verdict hero (this car's
//  bolt-seal + reuse state) over a 90-day uniqueness scan (uniqueness bar +
//  collision pairs + seal-of-record block). Deliberately a cryptographic-
//  uniqueness read, NOT 704's gauge, 706's mark matrix, or 690's reader trail.
//
//  Role: RAIL_ENGINEER (carrier/compliance). transportMode=rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railGate.ts +
//  railTrust.ts):
//    railGate.getGateActivity  EXISTS railGate.ts:102 {windowHours,limit} →
//        {events:[{railcarNumber,site,sealNumber,ediSeal,occurredAt,...}]}.
//        Tenant-scoped. The uniqueness scan runs ON-DEVICE across these REAL
//        gate-event seals: a seal number that appears on two different cars is
//        a collision (a reuse / spoof signal). The verdict, the uniqueness %,
//        and every collision pair are computed from this real feed — never
//        fabricated. An empty feed → honest "no seals scanned".
//    railTrust.flagSuspectCar  EXISTS railTrust.ts:27 {railcarNumber,reason?} —
//        "Flag seal" flags the car presenting the re-used seal for review.
//  VERIFIED ABSENT (honest state, never fabricated):
//    A railSeal.checkHashUniqueness endpoint with a cryptographic bolt-seal hash
//    ledger is not on disk; the scan uses the seal NUMBER on the real gate
//    events as the uniqueness key, and the seal-of-record shows the gate-record
//    ref (rge_id), never an invented 0x audit hash.
//  COUNTRY: trusted-trader US CTPAT · CA PIP · MX NEEC (OEA); ISO 17712-H seal.
//

import SwiftUI

struct RailSealHashCheckScreen: View {
    let theme: Theme.Palette
    var railcarNumber: String = "GATX 215704"

    var body: some View {
        Shell(theme: theme) {
            RailSealHashCheckBody(railcarNumber: railcarNumber)
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

private struct GateEvent708: Decodable, Identifiable {
    let id: String?
    let railcarNumber: String?
    let site: String?
    let sealNumber: String?
    let ediSeal: String?
    let occurredAt: String?
    var rowId: String { id ?? UUID().uuidString }
    var seal: String? {
        let s = (sealNumber ?? ediSeal)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty ?? true) ? nil : s
    }
}
private struct GateActivity708: Decodable { let events: [GateEvent708]? }
private struct GateInput708: Encodable { let windowHours: Int; let limit: Int }

// A detected reuse of one seal across two different cars.
private struct Collision708: Identifiable {
    let seal: String
    let first: GateEvent708
    let repeated: GateEvent708
    var id: String { seal }
}

// MARK: - Body

private struct RailSealHashCheckBody: View {
    let railcarNumber: String

    @Environment(\.palette) private var palette
    @State private var events: [GateEvent708] = []
    @State private var loading = true
    @State private var flagging = false
    @State private var flagMessage: String? = nil
    @State private var flagIsError = false
    @State private var regime = 0

    private let regimes: [(String, String, String)] = [
        ("US · CTPAT", "17712-H seal", "CTPAT"),
        ("CA · PIP", "17712-H seal", "PIP"),
        ("MX · NEEC", "OEA seal", "NEEC"),
    ]

    /// Every gate event carrying a seal, chronological.
    private var sealed: [GateEvent708] {
        events.filter { $0.seal != nil }.sorted { ($0.occurredAt ?? "") < ($1.occurredAt ?? "") }
    }
    private var scannedCount: Int { sealed.count }
    private var distinctSeals: Int { Set(sealed.compactMap { $0.seal }).count }

    /// A seal used on ≥2 distinct cars is a collision. first = earliest use.
    private var collisions: [Collision708] {
        var bySeal: [String: [GateEvent708]] = [:]
        for e in sealed { if let s = e.seal { bySeal[s, default: []].append(e) } }
        var out: [Collision708] = []
        for (seal, evs) in bySeal {
            let distinctCars = Set(evs.compactMap { $0.railcarNumber })
            if distinctCars.count >= 2 {
                let ordered = evs.sorted { ($0.occurredAt ?? "") < ($1.occurredAt ?? "") }
                if let f = ordered.first, let l = ordered.last { out.append(Collision708(seal: seal, first: f, repeated: l)) }
            }
        }
        return out.sorted { $0.seal < $1.seal }
    }

    /// The seal(s) presented by the car under review.
    private var mySeals: Set<String> { Set(sealed.filter { $0.railcarNumber == railcarNumber }.compactMap { $0.seal }) }
    private var myCollisions: [Collision708] { collisions.filter { mySeals.contains($0.seal) } }
    private var latestForCar: GateEvent708? { sealed.filter { $0.railcarNumber == railcarNumber }.last }
    private var reuseForCar: Bool { !myCollisions.isEmpty }

    private var uniquePct: Double {
        guard distinctSeals > 0 else { return 0 }
        return Double(distinctSeals - collisions.count) / Double(distinctSeals)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Seal hash check")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("bolt seal · car \(railcarNumber) · 17712-H")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4).lineLimit(1)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else {
                    verdictHero
                    scanCard
                    collisionHeader
                    collisionList
                    sealOfRecord
                    triBand
                    footerActions
                    if let m = flagMessage {
                        LifecycleCard(accentDanger: flagIsError) {
                            Text(m).font(EType.caption).foregroundStyle(flagIsError ? Brand.danger : Brand.success)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            Text("✦ CARRIER · RAIL · SEAL INTEGRITY")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("ISO 17712")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip("90-day scan", palette.textSecondary)
            chip("\(collisions.count) reuse", collisions.isEmpty ? Brand.success : Brand.danger)
            chip(regimes[regime].2.lowercased(), Brand.blue)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Verdict hero — reuse for THIS car, danger-washed on a hit.

    private var verdictHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(reuseForCar ? "SEAL HASH · REUSE DETECTED"
                                 : (scannedCount == 0 ? "SEAL HASH · NO SEALS SCANNED" : "SEAL HASH · UNIQUE"))
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(reuseForCar ? Brand.danger : (scannedCount == 0 ? Brand.warning : Brand.success))
                Spacer()
                Text(regimes[regime].2).font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [(reuseForCar ? Brand.danger : (scannedCount == 0 ? Brand.warning : Brand.success)).opacity(0.13), Brand.blue.opacity(0.06)],
                                       startPoint: .leading, endPoint: .trailing))
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill((reuseForCar ? Brand.danger : Brand.success).opacity(0.10)).frame(width: 48, height: 48)
                    Image(systemName: reuseForCar ? "exclamationmark.shield.fill" : "seal.fill")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(reuseForCar ? Brand.danger : Brand.success)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(reuseForCar ? "Hash already on record" : (scannedCount == 0 ? "No seals to scan" : "Seal is unique"))
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(heroDetail).font(.system(size: 11)).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    if let s = mySeals.first {
                        Text(masked(s)).font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundStyle(reuseForCar ? Brand.danger : palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(reuseForCar ? AnyShapeStyle(Brand.danger.opacity(0.55)) : AnyShapeStyle(LinearGradient.primary), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var heroDetail: String {
        if reuseForCar, let c = myCollisions.first {
            return "identical to a seal logged on car \(c.first.railcarNumber ?? "another car") at \(c.first.site ?? "a gate")."
        }
        if scannedCount == 0 { return "no bolt-seal reads are on file for the scan window, so no uniqueness verdict can be drawn." }
        return "\(railcarNumber)'s seal does not collide with any other car across the \(scannedCount)-seal scan."
    }

    private func masked(_ s: String) -> String {
        guard s.count > 8 else { return s }
        let head = s.prefix(8)
        return "\(head)…\(s.suffix(4))"
    }

    // MARK: 90-day uniqueness scan card.

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("90-DAY UNIQUENESS SCAN").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(scannedCount) seals · \(collisions.count) collision\(collisions.count == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(distinctSeals > 0 ? "\((uniquePct * 100).formatted(.number.precision(.fractionLength(uniquePct > 0.999 ? 2 : 1))))%" : "—")
                    .font(.system(size: 30, weight: .bold)).monospacedDigit()
                    .foregroundStyle(collisions.isEmpty ? Brand.success : Brand.danger)
                Text("unique").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 8)
                    Capsule().fill(collisions.isEmpty ? Brand.success : Brand.danger)
                        .frame(width: g.size.width * CGFloat(max(0.02, uniquePct)), height: 8)
                }
            }.frame(height: 8)
        }
        .padding(16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var collisionHeader: some View {
        HStack {
            Text("SEAL COLLISIONS · CROSS-CAR REUSE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Spacer()
        }
    }

    @ViewBuilder
    private var collisionList: some View {
        if collisions.isEmpty {
            EusoEmptyState(systemImage: "checkmark.seal",
                           title: scannedCount == 0 ? "No seals on file" : "No seal reuse",
                           subtitle: scannedCount == 0
                               ? "No bolt-seal reads are recorded in the scan window. Collisions surface here the moment a seal number repeats across two cars."
                               : "Every scanned seal is unique to one car. No CTPAT seal-spoof pattern in the last 90 days.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(collisions.enumerated()), id: \.element.id) { i, c in
                    collisionRow(c)
                    if i < collisions.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
            .padding(16)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.4)))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func collisionRow(_ c: Collision708) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(masked(c.seal)).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(Brand.danger)
                Spacer()
                Text("REUSE").font(.system(size: 8, weight: .heavy)).foregroundStyle(Brand.danger)
                    .padding(.horizontal, 8).frame(height: 18).background(Capsule().fill(Brand.danger.opacity(0.12)))
            }
            reuseLeg("first logged", c.first)
            reuseLeg("re-presented", c.repeated)
        }
        .padding(.vertical, 12)
    }

    private func reuseLeg(_ label: String, _ e: GateEvent708) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary).frame(width: 82, alignment: .leading)
            Text("\(relTime(e.occurredAt)) · car \(e.railcarNumber ?? "—") · \(e.site ?? "gate")")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textSecondary).lineLimit(1)
            Spacer()
        }
    }

    // MARK: Seal of record — the car's latest real gate event.

    private var sealOfRecord: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SEAL OF RECORD").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            recordRow("Type", "Bolt seal · ISO 17712-H")
            recordRow("Applied at", latestForCar.map { "\($0.site ?? "yard") · \(relTime($0.occurredAt))" } ?? "no gate record on file")
            recordRow("Gate record", latestForCar?.id ?? "—")
            recordRow("Last verified", latestForCar.map { relTime($0.occurredAt) } ?? (reuseForCar ? "reuse — verify now" : "—"))
        }
        .padding(16)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func recordRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textPrimary).lineLimit(1)
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

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: flagging ? "Flagging…" : "Flag seal", action: { Task { await flagSeal() } })
                .frame(maxWidth: .infinity)
                .disabled(flagging || !reuseForCar)
            RailSecondaryActionButton(
                title: "View original",
                sheetTitle: "Original seal record",
                lines: myCollisions.first.map { c in
                    ["Seal · \(masked(c.seal))",
                     "First logged · \(relTime(c.first.occurredAt))",
                     "First car · \(c.first.railcarNumber ?? "—")",
                     "First site · \(c.first.site ?? "gate")",
                     "Re-presented · \(relTime(c.repeated.occurredAt)) · car \(c.repeated.railcarNumber ?? "—")"]
                } ?? ["No collision to show — this car's seal is unique across the scan."],
                width: 130,
                systemImage: "seal")
        }
    }

    // MARK: Load + flag

    private func reload() async {
        loading = true
        let g: GateActivity708? = try? await EusoTripAPI.shared.query(
            "railGate.getGateActivity", input: GateInput708(windowHours: 2160, limit: 500))
        self.events = g?.events ?? []
        loading = false
    }

    private func flagSeal() async {
        flagging = true; flagMessage = nil
        struct In: Encodable { let railcarNumber: String; let reason: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "railTrust.flagSuspectCar",
                input: In(railcarNumber: railcarNumber, reason: "Re-used bolt-seal hash detected via 708 seal-hash uniqueness scan"))
            flagIsError = false
            flagMessage = "Seal flagged — car \(railcarNumber) is in the review queue for a re-used bolt seal."
        } catch {
            flagIsError = true
            flagMessage = "The flag didn't record. The scan above is unchanged — check your connection and try again."
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

#Preview("708 · Rail Seal Hash Check · Night") {
    RailSealHashCheckScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("708 · Rail Seal Hash Check · Light") {
    RailSealHashCheckScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
