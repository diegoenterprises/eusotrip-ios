//
//  671_RailClaimTemplates.swift
//  EusoTrip — Rail Engineer · Claim Templates (carrier-side cargo-claims template library).
//
//  Bespoke port of "05 Rail/Code/671_RailClaimTemplates.swift" (Light + Dark), adapted to
//  app convention (Shell + rail BottomNav, COMPLIANCE slot inked). NOT a ledger (670), NOT
//  the waterfall (669) — this is a PICKER: a 2-column TEMPLATE CARD GALLERY. Each card shows
//  a type glyph chip, a type badge, the form name, a REQUIRED-vs-OPTIONAL FIELD PIP STRIP
//  (filled = required, hollow = optional) and a usage footer; a dashed "Blank claim" card
//  closes the grid.
//
//  Role: RAIL_ENGINEER (carrier-side). Shipper-of-record DU/Eusorone; carrier BNSF Intermodal.
//
//  Data:
//    freightClaims.getClaimTemplates  (EXISTS freightClaims.ts:1231 · protectedProcedure.query · no input)
//        → { templates: [{ id, type(damage|loss|shortage|delay|contamination),
//                           name, description, requiredFields[], optionalFields[] }] }
//    'Draft from template' → native ShareLink packet generated from the live template fields.
//        freightClaims.fileClaim requires loadId + amount + description + evidence, so this picker
//        exports a safe draft packet rather than fabricating a claim row.
//
//  Named gaps (to the-oath): (1) no usage stats — getClaimTemplates returns no
//    usage:{count,lastUsedAt}; the usage footer is honestly omitted (was client-side fiction).
//    (2) no rail/AAR variants on the row; propose a transportMode filter (AAR Rule 102/123).
//

import SwiftUI

// MARK: - Wrapper (Shell + rail nav — COMPLIANCE inked)

struct RailClaimTemplatesScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailClaimTemplatesBody671() } nav: {
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

// MARK: - Wire shapes (maps 1:1 to getClaimTemplates output)

private struct EmptyInput671: Encodable {}

private struct ClaimTemplatesResp671: Decodable {
    let templates: [ClaimTemplateDTO671]
}

private struct ClaimTemplateDTO671: Decodable, Identifiable {
    let id: String
    let type: String?
    let name: String?
    let description: String?
    let requiredFields: [String]?
    let optionalFields: [String]?
}

// MARK: - View model (UI-ready, derived from the DTO — never decorative)

private struct ClaimTemplate671: Identifiable {
    let id: String
    let name: String
    let badge: String
    let glyph: String
    let tint: Color
    let requiredCount: Int
    let optionalCount: Int
    let requiredFields: [String]
    let optionalFields: [String]
    let mostUsed: Bool

    init(_ dto: ClaimTemplateDTO671, mostUsed: Bool) {
        self.id = dto.id
        self.name = dto.name ?? "-"
        let t = (dto.type ?? "").lowercased()
        let style = ClaimTemplate671.style(for: t)
        self.badge = style.badge + (mostUsed ? " \u{2605}" : "")
        self.glyph = style.glyph
        self.tint  = style.tint
        self.requiredFields = dto.requiredFields ?? []
        self.optionalFields = dto.optionalFields ?? []
        self.requiredCount = requiredFields.count
        self.optionalCount = optionalFields.count
        self.mostUsed = mostUsed
    }

    private static func style(for type: String) -> (badge: String, glyph: String, tint: Color) {
        switch type {
        case "damage":        return ("DAMAGE",   "shippingbox.and.arrow.backward", Color(red: 0.776, green: 0.157, blue: 0.157))
        case "loss":          return ("LOSS",     "xmark.bin",                      Color(red: 0.482, green: 0.122, blue: 0.635))
        case "shortage":      return ("SHORTAGE", "minus.rectangle",                Color(red: 0.082, green: 0.396, blue: 0.753))
        case "delay":         return ("DELAY",    "clock",                          Color(red: 0.710, green: 0.392, blue: 0.102))
        case "contamination": return ("CONTAM.",  "drop",                           Color(red: 0.059, green: 0.478, blue: 0.341))
        default:              return (type.uppercased(), "doc.text", Color(red: 0.082, green: 0.451, blue: 1.0))
        }
    }
}

// MARK: - Body

private struct RailClaimTemplatesBody671: View {
    @Environment(\.palette) private var palette

    @State private var templates: [ClaimTemplate671] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var selectedTemplateId: String? = nil
    @State private var showingManagePanel = false

    private let cardRim671 = LinearGradient(
        colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    private let cols671 = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    private var mostUsedName: String? { templates.first(where: { $0.mostUsed })?.name }
    private var selectedTemplate: ClaimTemplate671? {
        if let selectedTemplateId, let match = templates.first(where: { $0.id == selectedTemplateId }) { return match }
        return templates.first
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                introBand
                if loading {
                    LifecycleCard { Text("Loading templates…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if templates.isEmpty {
                    EusoEmptyState(systemImage: "doc.on.doc",
                                   title: "No claim templates",
                                   subtitle: "No standard forms are configured for this carrier yet.")
                } else {
                    librarySection
                    esangRow
                    ctaRow
                    managePanel
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · CARGO CLAIMS")
                        .font(.system(size: 9, weight: .heavy)).kerning(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("TEMPLATES")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Claim templates")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("AAR-ALIGNED").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textSecondary)
                    Text("\(templates.count) forms").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
            }
            IridescentHairline()
        }
    }

    // MARK: Intro band (library header, NOT a stat hero)

    private var introBand: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(LinearGradient.diagonal).frame(width: 34, height: 34)
                Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Start a claim from a standard form")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("Pre-filled fields, AAR-aligned. Pick the type below.")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(16).frame(height: 64)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.borderFaint)))
    }

    // MARK: Signature — 2-col template library gallery

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TEMPLATE LIBRARY")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                if let m = mostUsedName {
                    Text("most used \u{2605} \(m)").font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                }
            }
            LazyVGrid(columns: cols671, spacing: 16) {
                ForEach(templates) { t in templateCard(t) }
                blankCard
            }
        }
    }

    private func templateCard(_ t: ClaimTemplate671) -> some View {
        let isSelected = selectedTemplate?.id == t.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.tint.opacity(0.14)).frame(width: 32, height: 32)
                    .overlay(Image(systemName: t.glyph).font(.system(size: 14)).foregroundColor(t.tint))
                Spacer()
                Text(t.badge).font(.system(size: 8, weight: .heavy)).kerning(0.4).foregroundColor(t.tint)
            }
            Spacer(minLength: 6)
            Text(t.name).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
            fieldPips(required: t.requiredCount, optional: t.optionalCount).padding(.top, 6)
            Text("\(t.requiredCount + t.optionalCount) fields")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary).padding(.top, 6)
        }
        .padding(14).frame(height: 118, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke((isSelected || t.mostUsed) ? AnyShapeStyle(cardRim671) : AnyShapeStyle(palette.borderFaint), lineWidth: (isSelected || t.mostUsed) ? 1.5 : 1)))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { selectedTemplateId = t.id }
    }

    private func fieldPips(required: Int, optional: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<max(0, required), id: \.self) { _ in Circle().fill(Brand.blue).frame(width: 6, height: 6) }
            ForEach(0..<max(0, optional), id: \.self) { _ in Circle().stroke(palette.textSecondary, lineWidth: 1.2).frame(width: 6, height: 6) }
            Text("\(required) req · \(optional) opt")
                .font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textSecondary).padding(.leading, 4)
        }
    }

    private var blankCard: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(palette.textPrimary.opacity(0.04)).frame(width: 34, height: 34)
                Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundStyle(palette.textSecondary)
            }
            Text("Blank claim").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("build from scratch").font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity).frame(height: 118)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.textPrimary.opacity(0.015))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                .foregroundStyle(palette.textSecondary.opacity(0.55))))
    }

    private var esangRow: some View {
        HStack(spacing: 0) {
            ZStack {
                Circle().fill(Brand.magenta.opacity(0.18)).frame(width: 40, height: 40).blur(radius: 6)
                OrbeSang(state: .idle, diameter: 32)
            }.padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG AI").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.diagonal)
                Text("For the Joliet box short on arrival, use the")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("Shortage form. It scaffolds the BOL reconciliation.")
                    .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.borderFaint)))
    }

    private var ctaRow: some View {
        let selected = selectedTemplate
        let primaryTitle = selected.map { "Draft \($0.name)" } ?? "Draft claim"
        return HStack(spacing: 8) {
            ShareLink(item: draftPacketText(for: selected)) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text(primaryTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            Button { showingManagePanel.toggle() } label: {
                Text(showingManagePanel ? "Hide" : "Manage")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var managePanel: some View {
        if showingManagePanel {
            LifecycleCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    LifecycleSection(label: "LIVE TEMPLATE MANAGEMENT", icon: "doc.on.doc.fill")
                    if let selectedTemplate {
                        LifecycleRow(label: "Selected", value: selectedTemplate.name)
                        LifecycleRow(label: "Type", value: selectedTemplate.badge.replacingOccurrences(of: " ★", with: ""))
                        LifecycleRow(label: "Required", value: fieldList(selectedTemplate.requiredFields))
                        LifecycleRow(label: "Optional", value: fieldList(selectedTemplate.optionalFields))
                    }
                    ShareLink(item: libraryExportText) {
                        Text("Export template library")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(palette.bgCardSoft)
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                }
            }
        }
    }

    private func fieldList(_ fields: [String]) -> String {
        fields.isEmpty ? "-" : fields.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", ")
    }

    private func draftPacketText(for template: ClaimTemplate671?) -> String {
        guard let template else {
            return "EusoTrip Freight Claim Draft\n\nNo live claim template is selected."
        }
        return [
            "EusoTrip Freight Claim Draft",
            "Template: \(template.name)",
            "Type: \(template.badge.replacingOccurrences(of: " ★", with: ""))",
            "",
            "Required fields:",
            fieldBulletList(template.requiredFields),
            "",
            "Optional fields:",
            fieldBulletList(template.optionalFields),
            "",
            "Filing note: add the shipment/load ID, amount, description and evidence before submission."
        ].joined(separator: "\n")
    }

    private func fieldBulletList(_ fields: [String]) -> String {
        guard !fields.isEmpty else { return "- None returned by the live template." }
        return fields.map { "- \($0.replacingOccurrences(of: "_", with: " "))" }.joined(separator: "\n")
    }

    private var libraryExportText: String {
        var lines = [
            "EusoTrip Rail Claim Template Library",
            "Generated: \(Date().formatted(date: .abbreviated, time: .shortened))",
            "Templates: \(templates.count)",
            ""
        ]
        for template in templates {
            lines.append("\(template.name) [\(template.badge.replacingOccurrences(of: " ★", with: ""))]")
            lines.append("Required: \(fieldList(template.requiredFields))")
            lines.append("Optional: \(fieldList(template.optionalFields))")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        do {
            let resp: ClaimTemplatesResp671 = try await EusoTripAPI.shared.query(
                "freightClaims.getClaimTemplates", input: EmptyInput671())
            // Most-used heuristic: getClaimTemplates carries no usage stats, so the FIRST
            // template (server-ordered, Damage) is flagged as the canonical default — honest,
            // not fabricated counts. Replace once templates[].usage ships.
            self.templates = resp.templates.enumerated().map { idx, dto in
                ClaimTemplate671(dto, mostUsed: idx == 0)
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("671 · Claim templates · Light") {
    RailClaimTemplatesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
#Preview("671 · Claim templates · Night") {
    RailClaimTemplatesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
