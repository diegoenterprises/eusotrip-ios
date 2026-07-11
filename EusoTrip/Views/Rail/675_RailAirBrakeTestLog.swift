//
//  675_RailAirBrakeTestLog.swift
//  EusoTrip — Rail Engineer · Air-Brake Test Log (49 CFR §232.205).
//
//  Bespoke port of "05 Rail/Dark-SVG/675 Rail Air-Brake Test Log.svg".
//  ARCHETYPE = CERTIFICATION RECORD / CHECKLIST — a leakage-posture verdict
//  hero over a timestamped brake-test-sequence checklist, closed by a
//  Qualified-Mechanical-Person sign-off seal. Not a stat dashboard.
//
//  Role: RAIL_ENGINEER (carrier family). transportMode = rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getRailInspections EXISTS:2684 {limit} →
//        [{id,type,date,location,status,inspector,notes,passed}]. Brake-tagged
//        inspection rows ARE the certified test-sequence steps — each carries a
//        real timestamp + inspector. The screen renders ONLY steps on file; the
//        canonical §232 sequence positions with no record show PENDING.
//    HONEST GAP: the leakage psi/min reading, the QMP certify-and-seal write,
//    and per-step logging have no backing procedure (getAirBrakeTest /
//    logAirBrakeStep / certifyAirBrakeTest — STUB). Leakage is parsed from a
//    real inspection note when present, else shown as "not recorded" — never
//    a synthesized psi value.
//

import SwiftUI

private struct InspRow675: Decodable, Identifiable {
    let id: String?
    let type: String?
    let date: String?
    let status: String?
    let location: String?
    let inspector: String?
    let notes: String?
    let passed: Bool?
    var rowId: String { id ?? "\(date ?? "")-\(location ?? "")" }
}
private struct LimitIn675: Encodable { let limit: Int }

struct RailAirBrakeTestLogScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailAirBrakeTestLogBody() } nav: {
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

private struct RailAirBrakeTestLogBody: View {
    @Environment(\.palette) private var palette
    @State private var brakeInsp: [InspRow675] = []
    @State private var loading = true
    @State private var country = 0

    // The canonical §232.205 initial-terminal sequence. Each canonical step
    // binds to a real brake inspection when one is on file; otherwise PENDING.
    private let sequence = ["Charge brake pipe to 90 psi",
                            "Leakage test ≤ 5 psi/min",
                            "Service application + walk",
                            "Release & roll-by sign",
                            "EOT telemetry confirm"]
    private let regimes: [(String, String)] = [("US · 49 CFR §232", "initial terminal"),
                                               ("CA · TC freight car", "insp. rules"),
                                               ("MX · ARTF/NOM", "prueba de freno")]

    private var certifiedSteps: Int { min(brakeInsp.count, sequence.count) }
    private var allPass: Bool { !brakeInsp.isEmpty && brakeInsp.allSatisfy { $0.passed != false } }
    private var latestInspector: String? { brakeInsp.compactMap { $0.inspector }.first }
    /// Real leakage reading parsed from an inspection note, else nil.
    private var leakage: (value: Int, text: String)? {
        for i in brakeInsp {
            if let n = i.notes, let m = Self.psi(n) { return m }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Air-brake test")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("Aurora Rail Division · 49 CFR §232.205 · initial terminal")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else {
                    leakageHero
                    sequenceHeader
                    sequenceCard
                    sealBlock
                    regimeBand
                    footerActions
                }
            }
            .padding(.horizontal, 20).padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            Text("✦ RAIL ENGINEER · AIR-BRAKE TEST")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("§232.205").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip("Initial terminal", Brand.warning)
            chip("§232", palette.textSecondary)
            chip(brakeInsp.isEmpty ? "no tests" : "\(certifiedSteps)/\(sequence.count) steps", Brand.rail)
        }
    }
    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var leakageHero: some View {
        let ok = allPass
        let wash = brakeInsp.isEmpty
            ? [Brand.warning.opacity(0.12), Brand.blue.opacity(0.05)]
            : (ok ? [Brand.success.opacity(0.14), Brand.blue.opacity(0.06)]
                  : [Brand.danger.opacity(0.14), Brand.warning.opacity(0.10)])
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("BRAKE-PIPE LEAKAGE · §232.205")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(brakeInsp.isEmpty ? Brand.warning : (ok ? Brand.success : Brand.danger))
                Spacer()
                Text(brakeInsp.isEmpty ? "AWAITING" : (ok ? "PASSED" : "REVIEW"))
                    .font(.system(size: 10.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(brakeInsp.isEmpty ? Brand.warning : (ok ? Brand.success : Brand.danger))
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill((brakeInsp.isEmpty ? Brand.warning : (ok ? Brand.success : Brand.danger)).opacity(0.16)))
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: wash, startPoint: .leading, endPoint: .trailing))

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(leakage.map { "\($0.value)" } ?? "—")
                            .font(.system(size: 30, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text(leakage != nil ? "psi/min" : "not recorded")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    }
                    Text(brakeInsp.isEmpty ? "no air-brake test on file for this terminal"
                                           : "max 5 psi/min · \(certifiedSteps) of \(sequence.count) steps certified")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("STEPS").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
                    Text("\(certifiedSteps) / \(sequence.count)")
                        .font(.system(size: 16, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(ok ? Brand.success : Brand.warning)
                }
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var sequenceHeader: some View {
        HStack {
            Text("TEST SEQUENCE · §232").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text("\(certifiedSteps) of \(sequence.count)").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
    }

    private var sequenceCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(sequence.enumerated()), id: \.offset) { idx, name in
                let insp = idx < brakeInsp.count ? brakeInsp[idx] : nil
                let done = insp != nil
                let failed = insp?.passed == false
                stepRow(name: name, done: done, failed: failed,
                        meta: insp.map { "\(Self.shortTime($0.date)) · \($0.inspector ?? "QMP")" } ?? "pending · awaiting record")
                if idx < sequence.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(.horizontal, 16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func stepRow(name: String, done: Bool, failed: Bool, meta: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill((failed ? Brand.danger : (done ? Brand.success : Brand.warning)).opacity(0.14))
                    .frame(width: 22, height: 22)
                Image(systemName: failed ? "xmark" : (done ? "checkmark" : "clock"))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(failed ? Brand.danger : (done ? Brand.success : Brand.warning))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .bold))
                    .foregroundStyle(done ? palette.textPrimary : palette.textSecondary)
                Text(meta).font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }

    private var sealBlock: some View {
        let sealed = allPass && certifiedSteps == sequence.count
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill((sealed ? Brand.success : Brand.warning).opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: sealed ? "checkmark.seal.fill" : "seal")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(sealed ? Brand.success : Brand.warning)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(sealed ? "Certified · Qualified Mechanical Person" : "Awaiting QMP certification")
                    .font(.system(size: 12.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text(latestInspector.map { "\($0) · §232.205 initial terminal" }
                     ?? "sign-off records once the sequence is complete")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background((sealed ? Brand.success : Brand.warning).opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder((sealed ? Brand.success : Brand.warning).opacity(0.30), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var regimeBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == country ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == country ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { country = i } }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Sign & certify", action: {})
                .frame(maxWidth: .infinity)
                .disabled(!(allPass && certifiedSteps == sequence.count))
            Button {} label: {
                Text("Add defect").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132).frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }.buttonStyle(.plain).disabled(true)
        }
    }

    private func reload() async {
        loading = true
        let all: [InspRow675] = (try? await EusoTripAPI.shared.query(
            "railShipments.getRailInspections", input: LimitIn675(limit: 100))) ?? []
        brakeInsp = all.filter {
            let t = ($0.type ?? "").lowercased()
            return t.contains("brake") || t.contains("air")
        }
        loading = false
    }

    private static func psi(_ note: String) -> (Int, String)? {
        let ns = note as NSString
        guard let rx = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*psi"#, options: [.caseInsensitive]),
              let m = rx.firstMatch(in: note, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let s = ns.substring(with: m.range(at: 1))
        guard let v = Double(s) else { return nil }
        return (Int(v.rounded()), "\(s) psi")
    }
    private static func shortTime(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "recorded" }
        let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"; return f.string(from: d)
    }
}

#Preview("675 · Air-Brake Test Log · Night") {
    RailAirBrakeTestLogScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("675 · Air-Brake Test Log · Light") {
    RailAirBrakeTestLogScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
