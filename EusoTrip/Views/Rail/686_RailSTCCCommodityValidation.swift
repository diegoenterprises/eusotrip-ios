//
//  686_RailSTCCCommodityValidation.swift
//  EusoTrip — Rail · Shipper · STCC Commodity Validation (brick 686).
//
//  Verbatim SwiftUI port of "05 Rail/686 Rail STCC Commodity Validation" (Dark).
//  SHIPPER-SIDE CODE-MAPPING chip-chain: validate each 7-digit STCC before
//  tendering and auto-translate it to HTS/HS for cross-border, flagging
//  hazmat-linked commodities (49 CFR PIH). Composition follows function — a
//  validity+hazmat hero over a focus STCC → HTS → HS connected-chip chain plus
//  a validated line-item list.
//
//  Web parity: app/(rail)/commodity/validate/page.tsx.
//
//  tRPC wiring (fully-real reference-data reads):
//    • validate ← commodity.validateStcc   (EXISTS commodity.ts:631 — isValidStcc
//                  7-digit regex + STCC_SEED with hazmatLinked flag)
//    • HS / HTS ← commodity.searchGeneral   (EXISTS commodity.ts:650)
//    • STUB → the-oath: mapStccToHtsHs (the auto-translation link; today the HTS/HS
//                  chip shows the best searchGeneral candidate, labelled honestly).
//
//  RBAC: publicProcedure (reference data, read-only). transportMode = rail ·
//  tri-country code-regime band US STCC / CA CBSA HS6 / MX VUCEM NOM-HS.
//  BottomNav: canonical Shipper enum HOME · LOADS · [orb] · WALLET · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen root

struct RailSTCCCommodityValidationScreen: View {
    let theme: Theme.Palette
    /// Focus commodity + validated line-items from the wireframe. All are
    /// validated live against commodity.validateStcc.
    var focusStcc: String = "2812510"
    var lineStccs: [String] = ["0112210", "2911315", "2812143", "9990000"]

    init(theme: Theme.Palette = Theme.dark) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            RailSTCCValidationBody(focusStcc: focusStcc, lineStccs: lineStccs)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house.fill",       isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person.fill",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data (mirror validateStcc + searchGeneral)

private struct StccMatch686: Decodable { let stcc: String?; let description: String?; let hazmatLinked: Bool? }
private struct StccValidation686: Decodable { let valid: Bool; let stcc: String; let matched: StccMatch686? }
private struct HsResult686: Decodable { let hsCode: String?; let description: String? }
private struct HsSearch686: Decodable { let results: [HsResult686]; let count: Int }

private struct StccLine686: Identifiable {
    let id: String        // STCC
    let stcc: String
    var desc: String
    var hazmat: Bool
    var valid: Bool
}

// MARK: - Body

private struct RailSTCCValidationBody: View {
    let focusStcc: String
    let lineStccs: [String]
    @Environment(\.palette) private var palette

    @State private var focus: StccValidation686? = nil
    @State private var htsCandidate: String? = nil
    @State private var hsCandidate: String? = nil
    @State private var htsMapped = false
    @State private var lines: [StccLine686] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionNote: String? = nil

    private var focusValid: Bool { focus?.valid ?? false }
    private var focusHazmat: Bool { focus?.matched?.hazmatLinked ?? false }
    private var focusDesc: String {
        focus?.matched?.description ?? (focusValid ? "format valid · not in reference set" : "invalid STCC format")
    }
    private var validCount: Int { lines.filter { $0.valid }.count + (focusValid ? 1 : 0) }
    private var hazmatCount: Int { lines.filter { $0.hazmat }.count + (focusHazmat ? 1 : 0) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                chipRow
                if loading {
                    LifecycleCard { Text("Validating commodity codes…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    validityHero
                    mappingSection
                    regimeRow
                    if let note = actionNote {
                        Text(note).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(focusValid ? Brand.success : Brand.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("✦ SHIPPER · RAIL · STCC VALIDATION")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("STCC-CHK")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Commodity codes")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, 10)
            Text("\(focus?.matched?.description ?? "Commodity") · cross-border KC → MTY")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary).padding(.top, 4)
            IridescentHairline().padding(.top, 14)
        }
    }

    private var chipRow: some View {
        HStack(spacing: Space.s2) {
            miniChip(focusValid ? "valid" : "review", tint: focusValid ? Brand.success : Brand.warning)
            miniChip("\(hazmatCount) hazmat", tint: Color(hex: 0xFF6B5E))
            miniChip("x-border", tint: Color(hex: 0x6FA8FF))
        }
    }

    @ViewBuilder
    private func miniChip(_ text: String, tint: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .heavy)).tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(palette.bgCard))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Validity hero

    private var validityHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: focusValid ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(focusValid ? Brand.warning : Brand.danger)
                Text("STCC \(focusStcc) · \(focusValid ? "FORMAT VALID" : "FORMAT INVALID")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(focusValid ? Brand.warning : Brand.danger)
                Spacer(minLength: 4)
                if focusHazmat {
                    Text("HAZMAT").font(.system(size: 10, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(Color(hex: 0xFF6B5E))
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: 0xFF6B5E).opacity(0.14)))
                }
            }
            Text(focusStcc)
                .font(.system(size: 28, weight: .bold, design: .monospaced)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text("\(focusDesc)\(mapSuffix)")
                .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private var mapSuffix: String {
        if let hts = htsCandidate { return " · maps to HTS \(hts)" }
        return " · HTS map pending"
    }

    // MARK: Mapping section

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CODE MAPPING · STCC → HTS → HS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Color(hex: 0x9FB0BE))
                Spacer()
                Text("cross-border").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
            VStack(alignment: .leading, spacing: 0) {
                // Focus chip chain
                VStack(alignment: .leading, spacing: 10) {
                    Text("FOCUS COMMODITY · \((focus?.matched?.description ?? "COMMODITY").uppercased())")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        codeChip("STCC", focusStcc, Brand.warning)
                        Text("→").font(.system(size: 14, weight: .heavy)).foregroundStyle(palette.textTertiary)
                        codeChip("HTS", htsCandidate ?? "pending", Color(hex: 0x6FA8FF))
                        Text("→").font(.system(size: 14, weight: .heavy)).foregroundStyle(palette.textTertiary)
                        codeChip("HS", hsCandidate ?? "pending", Brand.success)
                    }
                    if !htsMapped {
                        Text("HTS/HS shown are the best searchGeneral candidate — the STCC→HTS→HS auto-map (mapStccToHtsHs) is pending; never auto-fills the customs field unverified.")
                            .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                Divider().padding(.horizontal, 16).overlay(palette.borderFaint)
                Text("OTHER LINE ITEMS · VALIDATED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                    lineRow(line)
                    if idx < lines.count - 1 { Divider().padding(.horizontal, 16).overlay(palette.borderFaint) }
                }
            }
            .padding(.vertical, 4)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    @ViewBuilder
    private func codeChip(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.5).foregroundStyle(tint)
            Text(value).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.14)))
    }

    @ViewBuilder
    private func lineRow(_ line: StccLine686) -> some View {
        HStack(spacing: 10) {
            Text(line.stcc)
                .font(.system(size: 12.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
            Text(line.desc).font(.system(size: 11.5)).foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if line.hazmat {
                ZStack {
                    Circle().fill(Color(hex: 0xFF6B5E)).frame(width: 16, height: 16)
                    Text("H").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                }
            }
            Text(line.valid ? "VALID" : "REVIEW")
                .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                .foregroundStyle(line.valid ? Brand.success : Brand.warning)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill((line.valid ? Brand.success : Brand.warning).opacity(0.16)))
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: Regime chips

    private var regimeRow: some View {
        HStack(spacing: Space.s2) {
            regimeChip("US · STCC", "7-digit rail", active: true)
            regimeChip("CA · HS", "CBSA HS6", active: false)
            regimeChip("MX · NOM", "VUCEM HS", active: false)
        }
    }

    @ViewBuilder
    private func regimeChip(_ title: String, _ sub: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? Color(hex: 0x6FA8FF) : palette.textSecondary)
            Text(sub).font(.system(size: 9, weight: .heavy))
                .foregroundStyle(active ? Color(hex: 0x6FA8FF) : palette.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(active ? Color(hex: 0x6FA8FF).opacity(0.20) : palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(active ? Color.clear : palette.borderFaint))
    }

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Confirm codes",
                      action: { confirmTapped() },
                      trailingIcon: "checkmark")
            RailSecondaryActionButton(
                title: "Lookup",
                sheetTitle: "STCC validation context",
                lines: lookupLines,
                systemImage: "magnifyingglass"
            )
        }
    }

    private var lookupLines: [String] {
        var l: [String] = []
        l.append("Focus \(focusStcc) · \(focusDesc)")
        l.append("HTS \(htsCandidate ?? "map pending") · HS \(hsCandidate ?? "map pending")")
        for line in lines {
            l.append("\(line.stcc) · \(line.desc) · \(line.valid ? "VALID" : "REVIEW")\(line.hazmat ? " · HAZMAT" : "")")
        }
        return l
    }

    private func confirmTapped() {
        let reviews = lines.filter { !$0.valid }.count + (focusValid ? 0 : 1)
        if reviews > 0 {
            actionNote = "\(reviews) code(s) need review — confirm is blocked until every STCC passes isValidStcc."
        } else {
            actionNote = "All \(validCount) codes valid · \(hazmatCount) hazmat-linked. Codes ready to auto-fill the tender commodityStcc."
        }
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil; actionNote = nil
        struct StccIn: Encodable { let stcc: String }
        struct GenIn: Encodable { let name: String; let limit: Int }
        do {
            let f = try await EusoTripAPI.shared.query(
                "commodity.validateStcc", input: StccIn(stcc: focusStcc)) as StccValidation686
            self.focus = f

            // HTS/HS candidate via searchGeneral on the focus description (honest —
            // the auto-map is a STUB; this is a candidate, not the verified map).
            if let desc = f.matched?.description, !desc.isEmpty {
                let hs = try? await EusoTripAPI.shared.query(
                    "commodity.searchGeneral", input: GenIn(name: desc, limit: 1)) as HsSearch686
                if let top = hs?.results.first?.hsCode, !top.isEmpty {
                    self.htsCandidate = formatHts(top)
                    self.hsCandidate = String(top.filter { $0.isNumber }.prefix(6))
                    self.htsMapped = false   // candidate only, never the verified auto-map
                }
            }

            var out: [StccLine686] = []
            for code in lineStccs {
                if let v = try? await EusoTripAPI.shared.query(
                    "commodity.validateStcc", input: StccIn(stcc: code)) as StccValidation686 {
                    out.append(StccLine686(
                        id: code, stcc: code,
                        desc: v.matched?.description ?? "unknown / not in reference set",
                        hazmat: v.matched?.hazmatLinked ?? false,
                        valid: v.valid))
                } else {
                    out.append(StccLine686(id: code, stcc: code, desc: "lookup failed", hazmat: false, valid: false))
                }
            }
            self.lines = out
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func formatHts(_ code: String) -> String {
        let digits = code.filter { $0.isNumber }
        if digits.count >= 6 {
            let a = digits.prefix(4)
            let b = digits.dropFirst(4).prefix(2)
            return "\(a).\(b)"
        }
        return code
    }
}

#Preview("686 · Rail STCC Validation · Night") {
    RailSTCCCommodityValidationScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("686 · Rail STCC Validation · Light") {
    RailSTCCCommodityValidationScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
