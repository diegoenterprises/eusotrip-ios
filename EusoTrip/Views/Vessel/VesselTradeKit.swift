//
//  VesselTradeKit.swift
//  EusoTrip — shared chrome for the Vessel Operator trade / terminal band
//  (screens 771 / 773 / 774 / 775 / 776 / 777 / 780 / 781).
//
//  These are the small, repeated primitives the golden Vessel-Operator
//  DETAIL header uses: the ✦ eyebrow + back chevron + h1 title + right-
//  aligned mono ID, the single iridescent hairline, plus a house error
//  card and a lightweight toast row. Extracted so every screen in the band
//  reads as one designer's work without copy-pasting the header eight times.
//

import SwiftUI

// MARK: - Detail header (eyebrow · back chevron · title · id · hairline)

struct VesselDetailHeader: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let eyebrow: String
    /// Short right-aligned caption beside the eyebrow (e.g. "LCL → FEU").
    var caption: String? = nil
    let title: String
    /// Right-aligned mono identifier under the title (e.g. a VES- booking).
    var idText: String? = nil
    /// Optional subtitle line under the title (used by the doc screens).
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text(eyebrow)
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
                if let caption {
                    Text(caption)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            HStack(alignment: .center, spacing: Space.s2) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let subtitle {
                        Text(subtitle)
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let idText {
                    Text(idText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.top, Space.s3)
            IridescentHairline()
                .padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }
}

// MARK: - Error card

struct VesselErrorCard: View {
    @Environment(\.palette) private var palette
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.danger)
            Text(text)
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintDanger)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Toast row (post-mutation acknowledgement)

struct VesselToastRow: View {
    @Environment(\.palette) private var palette
    let text: String
    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.success)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textPrimary).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintSuccess)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Honest-gap note (surfaces a named backend gap in-UI, WCAG-safe)

struct VesselGapNote: View {
    @Environment(\.palette) private var palette
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            Text(text)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

// MARK: - Trade Lane Documents (shared body for 776 CA-import / 777 MX-import)

/// Per-country configuration for the trade-lane-documents surface. Both
/// screens bind to the SAME real endpoint (getCrossBorderVesselDocs) keyed by
/// `direction`; only the hero framing, authority labels, and the action doc
/// differ per destination regime.
struct VesselTradeDocsConfig {
    let direction: String            // "CA_import" | "MX_import"
    let eyebrowCaption: String       // "CA IMPORT" | "MX IMPORT"
    let subtitle: String             // lane + authority summary
    let idText: String
    let authorityLabel: String       // "CBSA IMPORT FILINGS" | "ADUANA IMPORT FILINGS"
    let processTitle: String         // "CBSA CLEARANCE PROCESS" | "DESPACHO ADUANERO"
    let processStages: [String]      // stepper labels (last = the due action)
    let primaryCTA: String           // "File Form B3" | "Revisar NOM-050"
    let actionKeywords: [String]     // matches the doc that carries the action
    let gapNote: String

    static let caImport = VesselTradeDocsConfig(
        direction: "CA_import",
        eyebrowCaption: "CA IMPORT",
        subtitle: "Shanghai → Vancouver · CBSA import",
        idText: "VES-260602-C4B8A1",
        authorityLabel: "CORE TRADE + CBSA IMPORT FILINGS",
        processTitle: "CBSA CLEARANCE PROCESS",
        processStages: ["eManifest", "Risk cleared", "RPA granted", "B3 due"],
        primaryCTA: "File Form B3",
        actionKeywords: ["b3", "form b3"],
        gapNote: "Docs shown are the REAL CBSA import requirement set (getCrossBorderVesselDocs · CA_import). Per-doc attach + live release stage need a selected booking (getVesselShipmentDetail). File Form B3 → proposed vessel.fileFormB3 (no dedicated mutation yet)."
    )

    static let mxImport = VesselTradeDocsConfig(
        direction: "MX_import",
        eyebrowCaption: "MX IMPORT",
        subtitle: "Shanghai → Manzanillo · Aduana import",
        idText: "VES-260605-D7A2F1",
        authorityLabel: "CORE TRADE + ADUANA IMPORT FILINGS",
        processTitle: "DESPACHO ADUANERO · SEMÁFORO",
        processStages: ["COVE", "Pedimento", "Semáforo verde", "NOM"],
        primaryCTA: "Revisar NOM-050",
        actionKeywords: ["nom"],
        gapNote: "Docs shown are the REAL Aduana import requirement set (getCrossBorderVesselDocs · MX_import). Per-doc attach + live modulación need a selected booking (getVesselShipmentDetail). Revisar NOM-050 → proposed vessel.reviewNom (no dedicated mutation yet)."
    )
}

struct VesselTradeLaneDocsBody: View {
    @Environment(\.palette) private var palette
    let config: VesselTradeDocsConfig

    @State private var docs: [String] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    private var coreCount: Int { docs.filter { VesselDocClass.isCore($0) }.count }
    private var filingCount: Int { max(0, docs.count - coreCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · TRADE DOCS",
                caption: config.eyebrowCaption,
                title: "Trade lane documents",
                idText: config.idText,
                subtitle: subtitle
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else {
                    readinessHero
                    checklistSection
                    VesselGapNote(text: config.gapNote)
                    ctaPair
                }
                Color.clear.frame(height: Space.s6)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var subtitle: String {
        docs.isEmpty ? config.subtitle
            : "\(config.subtitle) · \(docs.count) required"
    }

    // Readiness hero: derived doc-set breakdown + clearance-process stepper.
    private var readinessHero: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(alignment: .top, spacing: Space.s3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Brand.info.opacity(0.14)).frame(width: 46, height: 46)
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 20, weight: .semibold)).foregroundStyle(Brand.info)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.processTitle)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(docs.count) required · \(coreCount) core · \(filingCount) filings")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(palette.textPrimary)
                    }
                    Spacer(minLength: 0)
                }
                // Clearance-process stepper (regulatory sequence · reference)
                processStepper
            }
        }
    }

    private var processStepper: some View {
        HStack(spacing: 0) {
            ForEach(Array(config.processStages.enumerated()), id: \.offset) { idx, stage in
                let isLast = idx == config.processStages.count - 1
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(isLast ? Brand.warning.opacity(0.18) : Brand.success.opacity(0.9))
                            .frame(width: isLast ? 16 : 12, height: isLast ? 16 : 12)
                        if isLast {
                            Circle().strokeBorder(Brand.warning, lineWidth: 2).frame(width: 16, height: 16)
                        }
                    }
                    Text(stage).font(.system(size: 8, weight: isLast ? .bold : .semibold))
                        .foregroundStyle(isLast ? Brand.warning : palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                if idx < config.processStages.count - 1 {
                    Rectangle().fill(idx < config.processStages.count - 2 ? Brand.success : palette.borderSoft)
                        .frame(height: 2).frame(maxWidth: .infinity)
                        .offset(y: -8)
                }
            }
        }
    }

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("DOCUMENTS · \(config.authorityLabel)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getCrossBorderVesselDocs")
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            if docs.isEmpty {
                EusoEmptyState(systemImage: "doc.on.doc",
                               title: "No document set returned",
                               subtitle: "The CBSA/Aduana required-document list will appear here once the trade service responds.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(docs.enumerated()), id: \.offset) { idx, name in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        docRow(name)
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func docRow(_ name: String) -> some View {
        let isAction = config.actionKeywords.contains { name.lowercased().contains($0) }
        let (icon, accent) = VesselDocClass.glyph(name, action: isAction)
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(accent.opacity(0.14)).frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(VesselDocClass.category(name, action: isAction)).font(.system(size: 10)).foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if isAction {
                Text("ACTION").font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.warning)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(palette.tintWarning))
            } else {
                Text("REQUIRED").font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(palette.tintNeutral))
            }
        }
        .padding(.vertical, Space.s3)
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: config.primaryCTA, action: {})
            Button {} label: {
                Text("All \(max(docs.count, 0)) docs").font(EType.title).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: 150, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
            }.buttonStyle(.plain)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 128)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 300)
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let direction: String; let mode: String; let hasHazmat: Bool }
        do {
            let names: [String] = (try await EusoTripAPI.shared.query(
                "vesselShipments.getCrossBorderVesselDocs",
                input: In(direction: config.direction, mode: "VESSEL", hasHazmat: false))) ?? []
            self.docs = names
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

/// Classifies a required-doc NAME into a category label + SF Symbol. Purely a
/// display heuristic over the real endpoint strings — never fabricates a doc.
enum VesselDocClass {
    static func isCore(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("bill of lading") || n.contains("commercial invoice")
            || n.contains("packing list") || n.contains("certificate of origin")
            || n.contains("canada customs invoice") || n.contains("cusma") || n.contains("factura")
    }
    static func glyph(_ name: String, action: Bool) -> (String, Color) {
        if action { return ("exclamationmark.triangle.fill", Brand.warning) }
        let n = name.lowercased()
        if n.contains("origin") || n.contains("cusma") { return ("rosette", Brand.info) }
        if n.contains("emanifest") || n.contains("vucem") || n.contains("cove") || n.contains("ams") { return ("antenna.radiowaves.left.and.right", Brand.escort) }
        if n.contains("pedimento") { return ("doc.text.magnifyingglass", Brand.escort) }
        if n.contains("agente") || n.contains("broker") { return ("person.text.rectangle", Brand.info) }
        if n.contains("cfia") || n.contains("permit") || n.contains("license") { return ("leaf", Brand.neutral) }
        return ("doc.text", Brand.info)
    }
    static func category(_ name: String, action: Bool) -> String {
        if action { return "PGA · review before delivery" }
        return isCore(name) ? "core trade document" : "customs / import filing"
    }
}
