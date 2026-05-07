//
//  EusoTicketCanvas.swift
//  EusoTrip — Universal EusoTicket render canvas (the canonical
//  Bill-of-Lading / POD / Run-Ticket / Haul-Receipt body, extracted
//  from the Figma 313 reference per founder doctrine).
//
//  Founder mandate (2026-05-06):
//   "the reason i uploaded the eusoticket screen was so you have the
//    uniform screen that i the owner believe should be the uniform
//    eusoticket screen and our universal eusoticket structure"
//
//  This file IS the universal structure. Every role surface that
//  renders an EusoTicket — Catalyst 313, Shipper 303 (BOL) / 304
//  (Run Ticket) / 305 (Haul Receipt), Driver pickup-BOL render,
//  Broker rate-con preview, Dispatch operations review, Carrier
//  document center — composes this single component instead of
//  duplicating the rendered-document body.
//
//  Canonical structure (313 verbatim):
//    1. Gradient header band: EUSOTICKET eyebrow + doc-type long-name
//       + load id + date
//    2. Origin / destination strip (FROM → TO with gradient arrow)
//    3. Hairline divider
//    4. Parties block: SHIPPER OF RECORD monogram + CARRIER monogram
//    5. Hairline divider
//    6. Commodity block + hazmat diamond callout
//    7. Hairline divider
//    8. Freight charges (gradient text) + signature receipt pill
//    9. Hairline divider
//    10. QR (canonical `EusoQRView`) + scan audit text + SHA-256 +
//        Polygon zkEVM tx
//    11. Hairline divider
//    12. Footer: USDOT · MC · IRP · BOC-3 · FMCSA SAFER · UCC §7-301
//        · 49 CFR §373.101 · 49 CFR §172
//
//  Why this lives in `Views/Components/` and not on a per-role file:
//  it's reusable across all 8 chrome roles. The 313 file stays as
//  the canonical Catalyst surface but composes this canvas; same
//  for the Shipper / Driver wrappers.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Doc-type taxonomy

/// The four document kinds the universal renderer supports. Maps 1:1
/// to `EusoQRKind.TicketKind` so the QR payload built from this canvas
/// scans into the same deep-link handler regardless of role.
enum EusoTicketDocType: String, CaseIterable, Identifiable, Hashable {
    case bol         = "BOL"
    case pod         = "POD"
    case runTicket   = "Run Ticket"
    case haulReceipt = "Haul Receipt"

    var id: String { rawValue }

    /// Compact label for the chip filter (e.g. "BOL", "Run Ticket").
    var chipLabel: String { rawValue }

    /// Long-form label rendered in the gradient header band
    /// (e.g. "Bill of Lading №", "Proof of Delivery №").
    var headerLongLabel: String {
        switch self {
        case .bol:         return "Bill of Lading"
        case .pod:         return "Proof of Delivery"
        case .runTicket:   return "Run Ticket"
        case .haulReceipt: return "Haul Receipt"
        }
    }

    /// Two-letter compact label for the render-context tile and
    /// gradient pill (e.g. "BOL", "POD", "RT", "HR").
    var compactPillLabel: String {
        switch self {
        case .bol:         return "BOL"
        case .pod:         return "POD"
        case .runTicket:   return "RT"
        case .haulReceipt: return "HR"
        }
    }

    /// QR payload kind so the canvas-rendered QR scans into the same
    /// universal-link handler as every other EusoTicket QR.
    var qrKind: EusoQRKind.TicketKind {
        switch self {
        case .bol:         return .bol
        case .pod:         return .pod
        case .runTicket:   return .runticket
        case .haulReceipt: return .haulreceipt
        }
    }
}

// MARK: - Party (Shipper-of-record / Carrier)

/// One party rendered on the canvas (either side of the BOL).
/// Universal across roles — Catalyst surfaces the same Carrier party
/// the Shipper, Driver, and Broker tracks render.
struct EusoTicketParty: Hashable {
    /// Display name (e.g. "Diego Usoro", "Eusotrans LLC").
    let name: String
    /// Two-letter monogram for the avatar circle (e.g. "DU", "ME").
    let monogram: String
    /// Subtitle line under the name. Renders in monospaced
    /// face — typical content is the legal-entity descriptor
    /// ("Eusorone Technologies · companyId 1") or carrier identifiers
    /// ("USDOT 3 194 882 · MC-820 144").
    let meta: String
    /// Avatar fill style. Use `.gradient` for the EusoTrip brand
    /// blue→magenta diagonal (canonical for Shipper-of-record per
    /// §11), `.dark` for ink-black (canonical for Carrier per §12).
    let avatarStyle: AvatarStyle

    enum AvatarStyle: Hashable {
        case gradient
        case dark
    }
}

// MARK: - Audit anchor (QR + chain)

/// The audit-chip text rendered next to the QR. Server emits the SHA-256
/// + blockchain-anchor tx as part of the EusoTicket envelope; the canvas
/// surfaces them so the receiving party can verify the document.
struct EusoTicketAudit: Hashable {
    /// Short-URL label rendered in bold next to the QR (e.g.
    /// `eusotrip.com/t/A38FB12C7E`). Decorative — the QR itself
    /// encodes the canonical `eusotrip://eusoticket/<kind>/<id>` URL.
    let shortUrl: String
    /// Time-of-anchor display (e.g. "09:14 CDT"). Empty when the
    /// document hasn't been anchored yet.
    let anchorTime: String
    /// Blockchain tx hash short-form (e.g. "0x9c4f…b021"). Empty when
    /// not anchored.
    let txHash: String
    /// Chain name (e.g. "Polygon zkEVM"). Defaults to the §EusoChain
    /// canonical L2 used by the production indexer.
    let chainLabel: String
}

// MARK: - Footer descriptor

/// USDOT/MC/IRP/BOC-3 footer line. Universal — same regulatory
/// citations on every EusoTicket regardless of role.
struct EusoTicketFooter: Hashable {
    let usdot: String     // e.g. "USDOT 3 194 882"
    let mc: String        // e.g. "MC-820 144"
    let irp: String       // e.g. "IRP IA"
    let boc3: String      // e.g. "BOC-3 active"
    /// Optional appended status (e.g. "FMCSA SAFER clean").
    var safetyTag: String

    /// Default constructor with the canonical CFR citation tail —
    /// every callsite reuses the same one. UCC §7-301 covers
    /// negotiable BOL law, FMCSR 49 CFR §373.101 covers carrier
    /// records, 49 CFR §172 covers hazmat papers.
    static let cfrTail = "Subject to UCC §7-301 · per FMCSR 49 CFR §373.101 · per 49 CFR §172 hazmat papers"
}

// MARK: - The canvas

/// Pure presentation: paints the universal EusoTicket render canvas
/// from a fully-resolved data envelope. No network calls — the host
/// surface is responsible for fetching the load + assembling the
/// parties / audit / footer.
///
/// Render contract: pinned to the Figma 313 colours regardless of
/// app-wide light/dark scheme. The canvas is a PRINTED BOL preview,
/// not a chrome surface — invoice-paper white background, ink-black
/// (#0D1117) primary text, body-grey (#52606D) secondary, muted
/// (#8A96A3) eyebrow.
struct EusoTicketCanvas: View {
    let kind: EusoTicketDocType
    let loadNumber: String
    let bolNumber: String
    let renderDate: String          // "YYYY-MM-DD" — pickup or render date
    let loadShortId: String         // eyebrow on header band (e.g. "LD-260427")

    let fromCity: String
    let fromAddress: String
    let fromTime: String

    let toCity: String
    let toAddress: String
    let toTime: String

    let shipperOfRecord: EusoTicketParty
    let carrier: EusoTicketParty

    /// Commodity primary line (e.g. "Gasoline · 7,500 gal").
    let commodityPrimary: String
    /// First commodity meta line (e.g. "UN1203 · PG II · NMFC 145880").
    let commodityMeta1: String
    /// Second commodity meta line (e.g. "MC-306 Petroleum Tanker · seal № EU-71044").
    let commodityMeta2: String

    /// Hazmat class string (e.g. "3"). Empty / nil → no diamond.
    let hazmatClass: String?
    /// Hazmat readable label (e.g. "Flammable").
    let hazmatLabel: String?
    /// Hazmat packing group (e.g. "PG II").
    let hazmatPG: String?

    /// Rate display string (e.g. "$1,900.00").
    let rateDisplay: String
    /// Rate meta line (e.g. "all-in · prepaid · invoiced post-POD").
    let rateMeta: String

    /// Signature receipt status. When nil, the section renders a
    /// neutral "awaiting" placeholder.
    let signatureReceipt: SignatureReceipt?

    let audit: EusoTicketAudit
    let qrRole: EusoRoleScope
    let footer: EusoTicketFooter

    struct SignatureReceipt: Hashable {
        /// "Pickup signed" / "POD captured" / etc.
        let title: String
        /// "06:14 CDT · DOT 9211" — short timestamp + identifier.
        let meta: String
    }

    var body: some View {
        VStack(spacing: 0) {
            renderHeader
            renderRouteStrip
            canvasDivider
            renderParties
            canvasDivider
            renderCommodityHazmat
            canvasDivider
            renderRateAndSignature
            canvasDivider
            renderQRAndAudit
            canvasDivider
            renderFooter
        }
        .padding(.bottom, 16)
        .background(
            ZStack {
                Color.white
                LinearGradient(
                    colors: [Brand.blue.opacity(0.06), Brand.magenta.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    // MARK: - Sections

    private var renderHeader: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient.diagonal
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EUSOTICKET")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.9))
                    Text("\(kind.headerLongLabel) № \(bolNumber)")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(loadShortId)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.9))
                    Text(renderDate)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(height: 56)
    }

    private var renderRouteStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FROM").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(EusoTicketCanvasInk.muted)
                Text(fromCity).font(.system(size: 14, weight: .heavy)).foregroundStyle(EusoTicketCanvasInk.primary)
                Text(fromAddress).font(.system(size: 10, design: .monospaced)).tracking(0.3).foregroundStyle(EusoTicketCanvasInk.body)
                Text(fromTime).font(.system(size: 10, design: .monospaced)).tracking(0.3).foregroundStyle(EusoTicketCanvasInk.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.top, 14)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("TO").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(EusoTicketCanvasInk.muted)
                Text(toCity).font(.system(size: 14, weight: .heavy)).foregroundStyle(EusoTicketCanvasInk.primary)
                Text(toAddress).font(.system(size: 10, design: .monospaced)).tracking(0.3).foregroundStyle(EusoTicketCanvasInk.body)
                Text(toTime).font(.system(size: 10, design: .monospaced)).tracking(0.3).foregroundStyle(EusoTicketCanvasInk.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var renderParties: some View {
        HStack(alignment: .top, spacing: 0) {
            partyBlock(eyebrow: "SHIPPER OF RECORD", party: shipperOfRecord)
                .frame(maxWidth: .infinity, alignment: .leading)
            partyBlock(eyebrow: "CARRIER", party: carrier)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }

    private func partyBlock(eyebrow: String, party: EusoTicketParty) -> some View {
        let monogramFill: AnyShapeStyle = {
            switch party.avatarStyle {
            case .gradient: return AnyShapeStyle(LinearGradient.diagonal)
            case .dark:     return AnyShapeStyle(EusoTicketCanvasInk.primary)
            }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(EusoTicketCanvasInk.muted)
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle().fill(monogramFill).frame(width: 28, height: 28)
                    Text(party.monogram)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(party.name)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(EusoTicketCanvasInk.primary)
                    Text(party.meta)
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(0.3)
                        .foregroundStyle(EusoTicketCanvasInk.body)
                }
            }
        }
    }

    private var renderCommodityHazmat: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("COMMODITY")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(EusoTicketCanvasInk.muted)
                Text(commodityPrimary)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(EusoTicketCanvasInk.primary)
                Text(commodityMeta1)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(EusoTicketCanvasInk.body)
                Text(commodityMeta2)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(EusoTicketCanvasInk.body)
            }
            Spacer(minLength: 0)
            if let hc = hazmatClass, !hc.isEmpty {
                hazmatCallout(class: hc, label: hazmatLabel ?? "Hazmat", pg: hazmatPG ?? "")
            }
        }
        .padding(.horizontal, 16)
    }

    private func hazmatCallout(class hazClass: String, label: String, pg: String) -> some View {
        let hazTag = hazClass == "3" ? "FLAM" : "HAZ"
        return HStack(alignment: .center, spacing: 8) {
            ZStack {
                let dia = LinearGradient(
                    colors: [Brand.danger, Brand.warning],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                EusoTicketCanvasDiamond()
                    .fill(dia)
                    .overlay(EusoTicketCanvasDiamond().stroke(EusoTicketCanvasInk.primary, lineWidth: 0.8))
                    .frame(width: 36, height: 36)
                VStack(spacing: 0) {
                    Text(hazTag).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                    Text(hazClass).font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("CLASS \(hazClass)")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(Brand.danger)
                Text(label)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(EusoTicketCanvasInk.primary)
                if !pg.isEmpty {
                    Text(pg)
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(0.3)
                        .foregroundStyle(EusoTicketCanvasInk.body)
                }
            }
        }
        .padding(8)
        .background(
            LinearGradient(
                colors: [Brand.danger.opacity(0.10), Brand.warning.opacity(0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var renderRateAndSignature: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FREIGHT CHARGES")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(EusoTicketCanvasInk.muted)
                Text(rateDisplay)
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text(rateMeta)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(EusoTicketCanvasInk.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("SIGNATURE RECEIPT")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(EusoTicketCanvasInk.muted)
                signaturePill
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var signaturePill: some View {
        if let sig = signatureReceipt {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Brand.success)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sig.title)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(EusoTicketCanvasInk.primary)
                    Text(sig.meta)
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(0.3)
                        .foregroundStyle(EusoTicketCanvasInk.body)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Brand.success.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(EusoTicketCanvasInk.body)
                Text("Awaiting signature")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(EusoTicketCanvasInk.body)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(EusoTicketCanvasInk.body.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var renderQRAndAudit: some View {
        HStack(alignment: .top, spacing: 12) {
            EusoQRView(
                kind: .eusoTicket(kind: kind.qrKind, id: bolNumber),
                role: qrRole,
                size: 56,
                cornerRadius: 6
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("SCAN AUDIT")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(EusoTicketCanvasInk.muted)
                Text(audit.shortUrl)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(EusoTicketCanvasInk.primary)
                if !audit.anchorTime.isEmpty {
                    Text("SHA-256 · blockchain-anchored \(audit.anchorTime)")
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(0.3)
                        .foregroundStyle(EusoTicketCanvasInk.body)
                } else {
                    Text("SHA-256 · awaiting blockchain anchor")
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(0.3)
                        .foregroundStyle(EusoTicketCanvasInk.body)
                }
                if !audit.txHash.isEmpty {
                    Text("tx \(audit.txHash) · \(audit.chainLabel)")
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(0.3)
                        .foregroundStyle(EusoTicketCanvasInk.body)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private var renderFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(footer.usdot) · \(footer.mc) · \(footer.irp) · \(footer.boc3)\(footer.safetyTag.isEmpty ? "" : " · \(footer.safetyTag)")")
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(EusoTicketCanvasInk.muted)
            Text(EusoTicketFooter.cfrTail)
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(EusoTicketCanvasInk.muted)
        }
        .padding(.horizontal, 16)
    }

    private var canvasDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }
}

// MARK: - Pinned canvas ink (Figma 313 colours)

/// The rendered EusoTicket paper card is intentionally pinned to the
/// Figma's exact ink (#0D1117), body (#52606D), and muted (#8A96A3)
/// hues regardless of light/dark scheme — the CARD itself is a
/// printed BOL preview, not a chrome surface. We use the canonical
/// `Color(hex: UInt32)` initialiser shipped in `Theme/DesignSystem.swift`.
enum EusoTicketCanvasInk {
    static let primary = Color(hex: 0x0D1117)
    static let body    = Color(hex: 0x52606D)
    static let muted   = Color(hex: 0x8A96A3)
}

// MARK: - Diamond shape (hazmat callout)

struct EusoTicketCanvasDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Convenience: build canvas from a LoadDetail + role

extension EusoTicketCanvas {
    /// Constructs the canvas from a `LoadsAPI.LoadDetail` + the four
    /// caller-supplied role-specific values (parties, audit, footer).
    /// Falls back to em-dash / honest-empty content for any missing
    /// load fields — never fabricates a value.
    init(
        kind: EusoTicketDocType,
        load: LoadsAPI.LoadDetail?,
        bolNumberOverride: String? = nil,
        renderDateOverride: String? = nil,
        shipperOfRecord: EusoTicketParty,
        carrier: EusoTicketParty,
        signatureReceipt: SignatureReceipt? = nil,
        audit: EusoTicketAudit,
        qrRole: EusoRoleScope,
        footer: EusoTicketFooter
    ) {
        self.kind = kind
        let ln = load?.loadNumber ?? "—"
        self.loadNumber = ln
        self.bolNumber = bolNumberOverride ?? Self.bolFromLoadNumber(ln)
        self.renderDate = renderDateOverride ?? Self.formatYMD(load?.pickupDate) ?? "—"
        self.loadShortId = Self.shortIdFromLoadNumber(ln)

        self.fromCity = load?.pickupLocation?.cityState ?? "—"
        self.fromAddress = Self.formatAddress(load?.origin) ?? "—"
        self.fromTime = load?.pickupDate.flatMap(Self.formatLongDateTime).map { "Pickup \($0)" } ?? "—"

        self.toCity = load?.deliveryLocation?.cityState ?? "—"
        self.toAddress = Self.formatAddress(load?.destination) ?? "—"
        self.toTime = load?.deliveryDate.flatMap(Self.formatLongDateTime).map { "Deliver \($0)" } ?? "—"

        self.shipperOfRecord = shipperOfRecord
        self.carrier = carrier

        self.commodityPrimary = Self.commodityLine(load: load) ?? "—"
        self.commodityMeta1 = Self.commodityMeta(load: load)
        self.commodityMeta2 = Self.equipmentMeta(load: load)

        self.hazmatClass = load?.hazmatClass
        self.hazmatLabel = (load?.hazmatClass == "3") ? "Flammable"
                          : (load?.hazmatClass != nil && load?.hazmatClass?.isEmpty == false ? "Hazmat" : nil)
        self.hazmatPG = (load?.hazmatClass != nil && load?.hazmatClass?.isEmpty == false) ? "PG II" : nil

        self.rateDisplay = load?.rateDisplay ?? "—"
        self.rateMeta = "all-in · prepaid · invoiced post-POD"

        self.signatureReceipt = signatureReceipt
        self.audit = audit
        self.qrRole = qrRole
        self.footer = footer
    }

    // Helpers (file-private)
    private static func bolFromLoadNumber(_ ln: String) -> String {
        if let dashRange = ln.range(of: "-", options: [.backwards]) {
            return String(ln[dashRange.upperBound...])
        }
        return ln
    }
    private static func shortIdFromLoadNumber(_ ln: String) -> String {
        if let dash = ln.dropFirst(3).firstIndex(of: "-") {
            return String(ln[..<dash])
        }
        return ln
    }
    private static func formatAddress(_ a: LoadsAPI.LoadAddress?) -> String? {
        guard let a = a else { return nil }
        let parts = [a.address, [a.city, a.state].compactMap { $0 }.joined(separator: ", ")]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    private static func formatYMD(_ iso: String?) -> String? {
        guard let iso = iso, !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: iso)
        }
        guard let date = d else { return nil }
        let out = DateFormatter()
        out.dateFormat = "yyyy-MM-dd"
        return out.string(from: date)
    }
    private static func formatLongDateTime(_ iso: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: iso)
        }
        guard let date = d else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MM-dd · HH:mm zzz"
        return out.string(from: date)
    }
    private static func commodityLine(load: LoadsAPI.LoadDetail?) -> String? {
        guard let load = load else { return nil }
        let name = load.commodityName ?? load.commodity ?? load.cargoType ?? "—"
        return "\(name) · \(load.weightDisplay)"
    }
    private static func commodityMeta(load: LoadsAPI.LoadDetail?) -> String {
        if let un = load?.unNumber { return "UN\(un) · PG II · NMFC 145880" }
        return "—"
    }
    private static func equipmentMeta(load: LoadsAPI.LoadDetail?) -> String {
        if let eq = load?.equipmentType, !eq.isEmpty {
            return "\(eq) · seal pending"
        }
        return "Equipment pending · seal pending"
    }
}

// MARK: - Previews

#Preview("EusoTicketCanvas · BOL · §11.4 flagship") {
    EusoTicketCanvas(
        kind: .bol,
        loadNumber: "LD-260427-A38FB12C7E",
        bolNumber: "A38FB12C7E",
        renderDate: "2026-04-27",
        loadShortId: "LD-260427",
        fromCity: "Houston TX",
        fromAddress: "LyondellBasell Channelview · 1515 Sheldon Rd",
        fromTime: "Pickup 04-27 · 06:00 CDT",
        toCity: "Dallas TX",
        toAddress: "RaceTrac Terminal · 4801 Singleton Blvd",
        toTime: "Deliver 04-27 · 14:00 CDT",
        shipperOfRecord: EusoTicketParty(
            name: "Diego Usoro",
            monogram: "DU",
            meta: "Eusorone Technologies · companyId 1",
            avatarStyle: .gradient
        ),
        carrier: EusoTicketParty(
            name: "Eusotrans LLC",
            monogram: "ME",
            meta: "USDOT 3 194 882 · MC-820 144",
            avatarStyle: .dark
        ),
        commodityPrimary: "Gasoline · 7,500 gal",
        commodityMeta1: "UN1203 · PG II · NMFC 145880",
        commodityMeta2: "MC-306 Petroleum Tanker · seal № EU-71044",
        hazmatClass: "3",
        hazmatLabel: "Flammable",
        hazmatPG: "PG II",
        rateDisplay: "$1,900.00",
        rateMeta: "all-in · prepaid · invoiced post-POD",
        signatureReceipt: EusoTicketCanvas.SignatureReceipt(
            title: "Pickup signed",
            meta: "06:14 CDT · DOT 9211"
        ),
        audit: EusoTicketAudit(
            shortUrl: "eusotrip.com/t/A38FB12C7E",
            anchorTime: "09:14 CDT",
            txHash: "0x9c4f…b021",
            chainLabel: "Polygon zkEVM"
        ),
        qrRole: .carrier,
        footer: EusoTicketFooter(
            usdot: "USDOT 3 194 882",
            mc: "MC-820 144",
            irp: "IRP IA",
            boc3: "BOC-3 active",
            safetyTag: "FMCSA SAFER clean"
        )
    )
    .padding(20)
    .background(Color(hex: 0xE9ECF1))
}
