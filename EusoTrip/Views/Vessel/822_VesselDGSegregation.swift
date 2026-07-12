//
//  822_VesselDGSegregation.swift
//  EusoTrip — Vessel Operator · DG Segregation.
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/822 Vessel DG Segregation.svg" (Light + Dark), built on
//  the canonical DesignSystem at the golden-era bar. Archetype = COMPLIANCE / MATRIX — the IMDG
//  class×class SEGREGATION MATRIX is the hero work surface, carried by no other screen. Hazmat gets
//  the most stringent lens: the separation codes are the published IMDG 7.2.4 reference, and the
//  flagged pairs are driven by the REAL compatibility engine, never invented. Role VESSEL_OPERATOR ·
//  nav COMPLIANCE inked.
//
//  Data / wiring (endpoints confirmed on disk this fire):
//    hazmat.getSegregationMatrix EXISTS frontend/server/routers/hazmat.ts:417 · query · no input ·
//      returns {matrix:[{classA, classB, compatible:Bool, nameA, nameB}], keys:[{code,name}],
//      regulation:"49 CFR 177.848"}. The REAL compatibility engine: any pair it marks
//      compatible=false is flagged as SEPARATION REQUIRED on the grid + counted in the hero. The
//      1/2/— separation-code granularity shown per cell is the published IMDG 7.2.4 reference table
//      (a regulatory constant, not tenant data), overlaid on top.
//    imdg.getClassMappings EXISTS imdg.ts:40 · query · no input — validates the DG class family.
//    imdg.markVesselManifest EXISTS imdg.ts:33 · mutation · input {loadId} · returns {success} —
//      wired to "Resolve conflict" when a loadId is threaded (clears the manifest to submitted).
//    STUB · named-gap handed to the-oath: getSegregationMatrix({loadId}) -> {pairs:{a,b,code,bay,
//      status}[]} — the LIVE per-bay stow overlay (which flagged pair is actually stowed together,
//      and where) is not modelled; the fix card renders honest guidance derived from the real flagged
//      pair rather than a fabricated container/bay.
//    Tri-country ERG band = published emergency-response references (US ERG2024 · CA CANUTEC ·
//      MX GRE-SCT) — constants.
//
//  DGClass822 / SegCell822 are file-scoped bespoke types. Dark + Light #Preview.
//
//  — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Real matrix decode (hazmat.getSegregationMatrix)

private struct SegMatrixPair822: Decodable {
    let classA: String?
    let classB: String?
    let compatible: Bool?
}
private struct SegMatrixResponse822: Decodable {
    let matrix: [SegMatrixPair822]?
    let regulation: String?
}

// MARK: - IMDG 7.2.4 published separation-code reference (regulatory constant)

private enum SegCode822 { case none, awayFrom, separatedFrom
    var glyph: String { switch self { case .none: return "—"; case .awayFrom: return "1"; case .separatedFrom: return "2" } }
}

private struct DGSegConstants822 {
    /// The manifest's dangerous-goods class family (the IMDG 7.2 reference subset).
    static let classes = ["2.1", "3", "5.1", "6.1", "8", "9"]

    /// IMDG 7.2.4 required-separation code for an unordered class pair (published table).
    static func code(_ a: String, _ b: String) -> SegCode822 {
        if a == b { return .none }
        let key = [a, b].sorted().joined(separator: "|")
        return table[key] ?? .none
    }
    private static let table: [String: SegCode822] = [
        "2.1|3":   .awayFrom,
        "2.1|5.1": .separatedFrom,
        "2.1|8":   .awayFrom,
        "3|5.1":   .separatedFrom,
        "3|8":     .awayFrom,
        "5.1|6.1": .awayFrom,
        "5.1|8":   .separatedFrom,
    ]
}

// MARK: - Screen wrapper (Shell + vessel nav · COMPLIANCE inked)

struct VesselDGSegregationScreen: View {
    let theme: Theme.Palette
    /// The vessel manifest this check scopes to. 0 = reference view (Resolve/markVesselManifest off).
    var loadId: Int

    init(theme: Theme.Palette, loadId: Int = 0) { self.theme = theme; self.loadId = loadId }

    var body: some View {
        Shell(theme: theme) {
            VesselDGSegregationBody822(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselDGSegregationBody822: View {
    @Environment(\.palette) private var palette
    let loadId: Int

    /// Real compatibility engine result: set of unordered class-pair keys flagged incompatible.
    @State private var flaggedPairs: Set<String> = []
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var resolving = false
    @State private var resolveDone = false
    @State private var resolveError: String? = nil

    private let classes = DGSegConstants822.classes

    // Derived — one real load drives the hero, the grid flags and the fix card ---
    private func pairKey(_ a: String, _ b: String) -> String { [a, b].sorted().joined(separator: "|") }
    private func flagged(_ a: String, _ b: String) -> Bool { a != b && flaggedPairs.contains(pairKey(a, b)) }

    /// Distinct flagged pairs among the displayed classes (upper triangle).
    private var flaggedList: [(String, String)] {
        var out: [(String, String)] = []
        for i in 0..<classes.count {
            for j in (i+1)..<classes.count where flagged(classes[i], classes[j]) {
                out.append((classes[i], classes[j]))
            }
        }
        return out
    }
    private var conflictCount: Int { flaggedList.count }
    private var leadConflict: (String, String)? { flaggedList.first }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                topBar
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else {
                    heroCard
                    matrixCard
                    fixCard
                    legend
                    ergBand
                    actionRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Eyebrow + top bar

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                Text("✦").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · DG SEGREGATION")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text(loadId > 0 ? "LOAD \(loadId)" : "IMDG 7.2")
                .font(EType.mono(.micro)).tracking(1.0).foregroundStyle(palette.textTertiary)
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("DG segregation").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text("checked live").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: Radius.xl).fill(palette.bgCardSoft).frame(height: 94)
            RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft).frame(height: 234)
        }.padding(.top, Space.s2)
    }
    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Segregation engine degraded").font(EType.bodyStrong).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Hero (numbers-first · danger-wash when a real conflict exists)

    private var heroCard: some View {
        let hasConflict = conflictCount > 0
        return HStack(alignment: .top, spacing: Space.s3) {
            Rectangle().fill(hasConflict ? Brand.danger : Brand.success).frame(width: 4).cornerRadius(2)
            // Hazmat diamond glyph
            diamond(text: leadConflict?.0 ?? "DG", tint: hasConflict ? Brand.danger : Brand.success)
            VStack(alignment: .leading, spacing: 4) {
                Text(hasConflict ? "SEGREGATION CONFLICT" : "SEGREGATION CLEAR")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(hasConflict ? Brand.danger : Brand.success)
                if let (a, b) = leadConflict {
                    (Text("Class \(a) ").foregroundStyle(palette.textPrimary)
                     + Text("✕").foregroundStyle(Brand.danger)
                     + Text(" Class \(b)").foregroundStyle(palette.textPrimary))
                        .font(.system(size: 22, weight: .bold))
                    Text("IMDG 7.2 · separation required · 49 CFR 177.848")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                } else {
                    Text("No pair conflict").font(.system(size: 22, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text("all class pairs pass the compatibility engine")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("PAIRS FLAGGED").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Text("\(conflictCount)").font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(hasConflict ? Brand.danger : palette.textPrimary)
                Text("\(classes.count) classes").font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background((hasConflict ? Brand.danger.opacity(0.10) : palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(hasConflict ? Brand.danger.opacity(0.32) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private func diamond(text: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(tint, lineWidth: 1.4))
                .frame(width: 34, height: 34)
                .rotationEffect(.degrees(45))
            Text(text).font(.system(size: text.count > 2 ? 10 : 14, weight: .heavy)).foregroundStyle(tint)
        }
        .frame(width: 48, height: 48)
    }

    // MARK: The IMDG segregation matrix (hero work surface)

    private var matrixCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("IMDG SEGREGATION MATRIX")
                Spacer()
                Text("getSegregationMatrix:417").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("required separation between stowed DG classes")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
                // Header row
                HStack(spacing: 4) {
                    Color.clear.frame(width: 30)
                    ForEach(classes, id: \.self) { c in
                        Text(c).font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textSecondary).frame(maxWidth: .infinity)
                    }
                }
                // Rows
                ForEach(classes, id: \.self) { rowClass in
                    HStack(spacing: 4) {
                        Text(rowClass).font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textSecondary).frame(width: 30, alignment: .trailing)
                        ForEach(classes, id: \.self) { colClass in
                            matrixCell(rowClass, colClass)
                        }
                    }
                }
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    @ViewBuilder
    private func matrixCell(_ row: String, _ col: String) -> some View {
        if row == col {
            // Diagonal (self) — neutral dot
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.06))
                Circle().fill(palette.textTertiary).frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity).frame(height: 26)
        } else {
            let code = DGSegConstants822.code(row, col)
            let isFlagged = flagged(row, col)
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(cellFill(code, flagged: isFlagged))
                if isFlagged {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Brand.danger.opacity(0.55), lineWidth: 1.5)
                }
                Text(code.glyph)
                    .font(.system(size: 12, weight: code == .none ? .regular : .bold))
                    .foregroundStyle(cellText(code, flagged: isFlagged))
            }
            .frame(maxWidth: .infinity).frame(height: 26)
        }
    }

    private func cellFill(_ code: SegCode822, flagged: Bool) -> Color {
        if flagged { return Brand.danger }
        switch code {
        case .none:          return Color.white.opacity(0.05)
        case .awayFrom:      return Brand.info.opacity(0.22)
        case .separatedFrom: return Brand.warning.opacity(0.24)
        }
    }
    private func cellText(_ code: SegCode822, flagged: Bool) -> Color {
        if flagged { return .white }
        switch code {
        case .none:          return palette.textTertiary
        case .awayFrom:      return Brand.info
        case .separatedFrom: return Brand.warning
        }
    }

    // MARK: Fix card (honest guidance from the real flagged pair)

    @ViewBuilder
    private var fixCard: some View {
        if let (a, b) = leadConflict {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.danger.opacity(0.14)).frame(width: 40, height: 40)
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 15, weight: .bold)).foregroundStyle(Brand.danger)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Separate Class \(a) from Class \(b)")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text("relocate one to a non-adjacent bay to clear the conflict")
                        .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                Text("ACTION").font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.danger)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Brand.danger.opacity(0.14)))
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        // No flagged pair → no fix card (honest: nothing to resolve).
    }

    // MARK: Code legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("SEPARATION CODE · IMDG 7.2")
            HStack(spacing: Space.s4) {
                legendChip(glyph: "1", fill: Brand.info.opacity(0.22), fg: Brand.info, label: "away from")
                legendChip(glyph: "2", fill: Brand.warning.opacity(0.24), fg: Brand.warning, label: "separated from")
                legendChip(glyph: "2", fill: Brand.danger, fg: .white, label: "flagged", ring: true)
                Spacer(minLength: 0)
            }
        }
    }
    private func legendChip(glyph: String, fill: Color, fg: Color, label: String, ring: Bool = false) -> some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill).frame(width: 20, height: 18)
                if ring { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Brand.danger.opacity(0.55), lineWidth: 1.2).frame(width: 20, height: 18) }
                Text(glyph).font(.system(size: 11, weight: .bold)).foregroundStyle(fg)
            }
            Text(label).font(.system(size: 11)).foregroundStyle(ring ? Brand.danger : palette.textSecondary)
        }
    }

    // MARK: Tri-country ERG band (regulatory reference)

    private var ergBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("EMERGENCY RESPONSE GUIDE · BY COUNTRY")
                Spacer()
                Text(loadId > 0 ? "LOAD \(loadId)" : "—").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s2) {
                ergChip(active: true,  code: "US", ref: "ERG2024 · active")
                ergChip(active: false, code: "CA", ref: "CANUTEC")
                ergChip(active: false, code: "MX", ref: "GRE-SCT")
            }
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
    private func ergChip(active: Bool, code: String, ref: String) -> some View {
        HStack(spacing: 6) {
            Text(code).font(.system(size: 9.5, weight: .heavy)).foregroundStyle(active ? Brand.info : palette.textSecondary)
            Text(ref).font(.system(size: 9.5, weight: .bold)).foregroundStyle(active ? Brand.info : palette.textPrimary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(active ? Brand.info.opacity(0.12) : palette.bgCard)
        .overlay(Capsule().strokeBorder(active ? Brand.info.opacity(0.35) : palette.borderFaint))
        .clipShape(Capsule())
    }

    // MARK: Actions

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let e = resolveError { Text(e).font(EType.caption).foregroundStyle(Brand.danger).fixedSize(horizontal: false, vertical: true) }
            if resolveDone { Text("Manifest marked clear · vessel manifest submitted.").font(EType.caption).foregroundStyle(Brand.success) }
            HStack(spacing: Space.s2) {
                CTAButton(title: resolving ? "Resolving…" : "Resolve conflict",
                          action: { Task { await resolve() } },
                          isLoading: resolving || loadId == 0)
                    .frame(maxWidth: .infinity)
                Button(action: {}) {
                    Text("Class table")
                        .font(EType.title).foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain).frame(maxWidth: 148)
            }
            if loadId == 0 {
                Text("Open from a manifest to resolve + submit.")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Load + resolve

    private func load() async {
        loading = true; loadError = nil
        do {
            let resp: SegMatrixResponse822 = try await EusoTripAPI.shared.queryNoInput("hazmat.getSegregationMatrix")
            var flags: Set<String> = []
            for pair in (resp.matrix ?? []) {
                if pair.compatible == false, let a = pair.classA, let b = pair.classB {
                    // Only flag pairs within the displayed DG class family.
                    if classes.contains(a) && classes.contains(b) {
                        flags.insert([a, b].sorted().joined(separator: "|"))
                    }
                }
            }
            flaggedPairs = flags
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func resolve() async {
        guard loadId > 0 else { return }
        resolving = true; resolveError = nil; resolveDone = false
        struct In822: Encodable { let loadId: Int }
        struct Ack822: Decodable { let success: Bool? }
        do {
            let _: Ack822 = try await EusoTripAPI.shared.mutation("imdg.markVesselManifest", input: In822(loadId: loadId))
            resolveDone = true
        } catch {
            resolveError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        resolving = false
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }
}

// MARK: - Previews

#Preview("822 · Vessel DG Segregation · Night") {
    VesselDGSegregationScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("822 · Vessel DG Segregation · Light") {
    VesselDGSegregationScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
