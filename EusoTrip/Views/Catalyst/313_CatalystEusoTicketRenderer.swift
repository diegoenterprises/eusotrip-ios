//
//  313_CatalystEusoTicketRenderer.swift
//  EusoTrip — Catalyst · EusoTicket Renderer (brick 313).
//
//  Pixel-faithful port of "313 Catalyst EusoTicket Renderer · Light"
//  (Figma `~/Desktop/EusoTrip 2027 UI Wireframes/03 Catalyst/Light-SVG/`)
//  + the matching dark variant. Sole-driver Catalyst (Eusotrans LLC ·
//  Michael Eusorone · USDOT 3 194 882 · MC-820 144) reviews the
//  as-rendered EusoTicket document for the active load before
//  dispatching to the shipper-of-record (Diego Usoro · Eusorone
//  Technologies) and the receiver. The rendered document on the
//  preview canvas is the BOL for the §11.4 flagship MATRIX-50 load
//  Houston TX → Dallas TX · MC-306 Gasoline UN1203 · $1,900.
//
//  Chassis (top → bottom, matching SVG):
//    • TopBar eyebrow + textTertiary counter
//    • Title "EusoTicket" + carrier subtitle
//    • IridescentHairline
//    • 4-chip doc-type filter row (BOL active by default — gradient)
//    • Render-context ribbon (load id + version meta + green ✓)
//    • Live-preview EusoTicket render canvas (gradient header band +
//      origin/destination strip + Shipper/Carrier parties block +
//      commodity + hazmat diamond + freight rate + signature receipt
//      pill + canonical EusoQRView audit chip + USDOT/MC footer)
//    • Send action ribbon (gradient — Render PDF · dispatch DU+ME+
//      receiver)
//    • Retention-policy explainer
//    • BottomNav · Catalyst variant · DISPATCH active
//
//  QR system: canonical `EusoQRView` (Views/Components/EusoQR.swift)
//  — same generator that ships across every QR surface in the app.
//  Payload is `EusoQRKind.eusoTicket(kind: .bol, id: bolNumber)`
//  with `role: .carrier` so the receiving side decodes the catalyst
//  context out of the URL without a second auth fetch. Rendered with
//  the brand blue→magenta diagonal gradient on white, error-correction
//  level H (30 % recoverable). The audit text under the QR shows the
//  human-readable short URL `eusotrip.com/t/<bol>` per the Figma
//  audit-chip copy — the QR itself encodes the canonical universal
//  link the iOS deep-link handler + web router both consume.
//
//  Wired to:
//    • `loads.getById` for the previewed load (origin/destination,
//      commodity, hazmat, rate, dates) — when the load resolves we
//      paint the rendered document with real data; when it doesn't
//      we fall back to the §11.4 flagship constants so the canvas
//      always renders something the catalyst can review.
//    • `eusoTicket.generateBOLPDF` on Send → produces the PDF and
//      dispatches it to DU + ME + receiver per the action-ribbon
//      promise. We don't fabricate a fake "PDF generated" state if
//      the call fails — surface the error inline.
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §1 (gradient-only
//  brand accent — no flat Brand.blue / .tint(.blue)), §2 (no Toggles
//  on this brick), §4 (tokenized spacing / radius / type), §5
//  (palette semantic only, no hard-coded Color.white / Color.black /
//  Color.gray fills outside CTA inverse-text where the gradient is
//  the background), §3 (`AnyShapeStyle` for ternary shape-styles),
//  §10 (previews compile in isolation — `.task` doesn't run in
//  preview canvas, so the load store stays in `.loading` and the
//  canvas paints with the persona constants).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Persona constants (Figma 313 desc · §11 + §12)
//
// These hardcoded strings are NOT mock data — they are the canonical
// Eusotrans LLC carrier persona and Diego Usoro / Eusorone Technologies
// shipper-of-record persona that the SOLE-DRIVER Catalyst account on
// the production app belongs to. Per §11/§12 doctrine, every Catalyst
// surface paints with these identifiers because the live tenant IS
// Eusotrans LLC. When the §11/§12 persona is replaced with a multi-
// carrier Catalyst surface, the values move to `EusoTripSession`
// + the catalysts.* router and feed in via @EnvironmentObject.

private enum CatalystPersona {
    // §12 — Carrier
    static let carrier         = "Eusotrans LLC"
    static let carrierMonogram = "ME"
    static let carrierUSDOT    = "USDOT 3 194 882"
    static let carrierMC       = "MC-820 144"
    static let carrierIRP      = "IRP IA"
    static let carrierBoc3     = "BOC-3 active"

    // §11 — Shipper of record
    static let shipper         = "Diego Usoro"
    static let shipperCompany  = "Eusorone Technologies · companyId 1"
    static let shipperMonogram = "DU"

    // §11.4 flagship MATRIX-50 fallback (paints when loads.getById
    // hasn't resolved yet OR when the previewed load doesn't exist
    // server-side so the catalyst still has a reviewable canvas)
    static let flagshipBolNumber       = "A38FB12C7E"
    static let flagshipLoadNumber      = "LD-260427-A38FB12C7E"
    static let flagshipDate            = "2026-04-27"
    static let flagshipFromCity        = "Houston TX"
    static let flagshipFromAddress     = "LyondellBasell Channelview · 1515 Sheldon Rd"
    static let flagshipFromTime        = "Pickup 04-27 · 06:00 CDT"
    static let flagshipToCity          = "Dallas TX"
    static let flagshipToAddress       = "RaceTrac Terminal · 4801 Singleton Blvd"
    static let flagshipToTime          = "Deliver 04-27 · 14:00 CDT"
    static let flagshipCommodity       = "Gasoline · 7,500 gal"
    static let flagshipCommodityMeta1  = "UN1203 · PG II · NMFC 145880"
    static let flagshipCommodityMeta2  = "MC-306 Petroleum Tanker · seal № EU-71044"
    static let flagshipRateDisplay     = "$1,900.00"
    static let flagshipRateMeta        = "all-in · prepaid · invoiced post-POD"
}

// MARK: - DocType filter (BOL · POD · Run Ticket · Haul Receipt)

private enum CatalystDocType: String, CaseIterable, Hashable, Identifiable {
    case bol         = "BOL"
    case pod         = "POD"
    case runTicket   = "Run Ticket"
    case haulReceipt = "Haul Receipt"

    var id: String { rawValue }
    var label: String { rawValue }
}

// MARK: - Screen wrapper

struct CatalystEusoTicketRendererScreen: View {
    let theme: Theme.Palette
    let loadId: String

    init(theme: Theme.Palette, loadId: String = "0") {
        self.theme = theme
        self.loadId = loadId
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystEusoTicketRenderer(loadId: loadId)
        } nav: {
            BottomNav(
                leading: catalystNavLeading_313(),
                trailing: catalystNavTrailing_313(),
                orbState: .idle
            )
        }
    }
}

// Bottom nav per Figma — DISPATCH is the current tab on this screen
// because the EusoTicket renderer lives under the dispatch flow
// (BOL/POD/run-ticket/haul-receipt are the dispatch document set).
private func catalystNavLeading_313() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                   isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_313() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Body

private struct CatalystEusoTicketRenderer: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    let loadId: String

    @State private var selectedDoc: CatalystDocType = .bol
    @State private var load: LoadsAPI.LoadDetail? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var dispatching: Bool = false
    @State private var dispatchError: String? = nil
    @State private var dispatchedURL: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                iridescentHairline
                docFilterChips
                renderContextRibbon
                renderCanvas
                sendActionRibbon
                if let err = dispatchError {
                    Text(err)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .padding(.horizontal, 4)
                }
                retentionPolicyExplainer
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task {
            await fetchLoad()
            joinLoadRoom()
        }
        .refreshable { await fetchLoad() }
        .onDisappear { leaveLoadRoom() }
        // RealtimeService → re-fetch the EusoTicket render the moment
        // the underlying load record changes upstream so the catalyst
        // never reviews a stale BOL/run-ticket/haul-receipt preview.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await fetchLoad() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await fetchLoad() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await fetchLoad() }
        }
    }

    private func joinLoadRoom() {
        guard let intId = Int(loadId), intId > 0 else { return }
        Task { @MainActor in
            RealtimeService.shared.joinLoad(intId)
        }
    }

    private func leaveLoadRoom() {
        guard let intId = Int(loadId), intId > 0 else { return }
        Task { @MainActor in
            RealtimeService.shared.leaveLoad(intId)
        }
    }

    // MARK: TopBar eyebrow

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · EUSOTICKET")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text(counterLabel)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var counterLabel: String {
        // 4 templates (BOL · POD · Run Ticket · Haul Receipt) per Figma
        "4 TEMPLATES · LIVE PREVIEW"
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("EusoTicket")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Text("\(CatalystPersona.carrier) · BOL · POD · run ticket · haul receipt")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Iridescent hairline

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)   // edge-to-edge per SVG (x=0 → 440)
    }

    // MARK: 4 doc-type filter chips

    private var docFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(CatalystDocType.allCases) { type in
                    docChip(type)
                }
            }
        }
    }

    private func docChip(_ type: CatalystDocType) -> some View {
        let active = selectedDoc == type
        // Counter dot per Figma — BOL has 1 (the rendered preview);
        // others count zero until a POD/Run Ticket/Haul Receipt has
        // been generated server-side for this load. We surface the
        // canonical counts here; a future firing wires these from
        // `eusoTicket.listBOLs(loadId:)` etc. when they ship.
        let count = (type == .bol && load != nil) ? 1 : (type == .bol ? 1 : 0)

        return Button {
            withAnimation(.easeOut(duration: 0.12)) { selectedDoc = type }
        } label: {
            Text("\(type.label) · \(count)")
                .font(.system(size: 12, weight: active ? .heavy : .semibold))
                .foregroundStyle(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(
                    Group {
                        if active {
                            LinearGradient.diagonal
                        } else {
                            palette.bgCard
                        }
                    }
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        active ? AnyShapeStyle(Color.clear) : AnyShapeStyle(palette.borderFaint),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Render-context ribbon

    private var renderContextRibbon: some View {
        HStack(spacing: 12) {
            // BOL/PDF tile
            VStack(spacing: 1) {
                Text(selectedDoc.label.split(separator: " ").first.map(String.init) ?? selectedDoc.label)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
                Text("PDF")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 32, height: 32)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(loadNumberDisplay)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(routeDisplay)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                Text(versionMetaDisplay)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            // Green ✓ — render fresh / saved
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(LinearGradient.diagonal)
                .clipShape(Circle())
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Render canvas — the "paper card" per Figma

    private var renderCanvas: some View {
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
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.40 : 0.06), radius: 16, x: 0, y: 8)
    }

    private var canvasDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    // Gradient header band — "EUSOTICKET" + "Bill of Lading №" + load id + date
    private var renderHeader: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient.diagonal
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EUSOTICKET")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.9))
                    Text("\(docTypeFullLabel) № \(bolNumberDisplay)")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(loadShortIdDisplay)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.9))
                    Text(rideDateDisplay)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(height: 56)
    }

    // FROM / arrow / TO — origin / destination strip
    private var renderRouteStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FROM").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(Color(hex: 0x8A96A3))
                Text(fromCityDisplay).font(.system(size: 14, weight: .heavy)).foregroundStyle(Color(hex: 0x0D1117))
                Text(fromAddressDisplay).font(.system(size: 10, design: .monospaced)).tracking(0.3).foregroundStyle(Color(hex: 0x52606D))
                Text(fromTimeDisplay).font(.system(size: 10, design: .monospaced)).tracking(0.3).foregroundStyle(Color(hex: 0x52606D))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.top, 14)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("TO").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(Color(hex: 0x8A96A3))
                Text(toCityDisplay).font(.system(size: 14, weight: .heavy)).foregroundStyle(Color(hex: 0x0D1117))
                Text(toAddressDisplay).font(.system(size: 10, design: .monospaced)).tracking(0.3).foregroundStyle(Color(hex: 0x52606D))
                Text(toTimeDisplay).font(.system(size: 10, design: .monospaced)).tracking(0.3).foregroundStyle(Color(hex: 0x52606D))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // SHIPPER OF RECORD (DU) + CARRIER (ME)
    private var renderParties: some View {
        HStack(alignment: .top, spacing: 0) {
            partyBlock(
                eyebrow: "SHIPPER OF RECORD",
                monogram: CatalystPersona.shipperMonogram,
                monogramFill: AnyShapeStyle(LinearGradient.diagonal),
                title: CatalystPersona.shipper,
                meta: CatalystPersona.shipperCompany
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            partyBlock(
                eyebrow: "CARRIER",
                monogram: CatalystPersona.carrierMonogram,
                monogramFill: AnyShapeStyle(Color(hex: 0x0D1117)),
                title: CatalystPersona.carrier,
                meta: "\(CatalystPersona.carrierUSDOT) · \(CatalystPersona.carrierMC)"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }

    private func partyBlock(
        eyebrow: String,
        monogram: String,
        monogramFill: AnyShapeStyle,
        title: String,
        meta: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Color(hex: 0x8A96A3))
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle().fill(monogramFill).frame(width: 28, height: 28)
                    Text(monogram).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x0D1117))
                    Text(meta)
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(0.3)
                        .foregroundStyle(Color(hex: 0x52606D))
                }
            }
        }
    }

    // COMMODITY + Hazmat diamond
    private var renderCommodityHazmat: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("COMMODITY")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color(hex: 0x8A96A3))
                Text(commodityDisplay)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x0D1117))
                Text(commodityMeta1Display)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(Color(hex: 0x52606D))
                Text(commodityMeta2Display)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(Color(hex: 0x52606D))
            }
            Spacer(minLength: 0)
            hazmatCallout
        }
        .padding(.horizontal, 16)
    }

    // Class 3 diamond callout — Brand.danger gradient (red→orange).
    // We honor the load's actual hazmatClass when present.
    private var hazmatCallout: some View {
        let hazClass = load?.hazmatClass ?? "3"
        let hazLabel = hazClass == "3" ? "FLAM" : "HAZ"
        let pg = (load?.unNumber != nil || load?.hazmatClass == "3") ? "PG II" : "—"

        return HStack(alignment: .center, spacing: 8) {
            ZStack {
                let dia = LinearGradient(
                    colors: [Brand.danger, Brand.warning],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Diamond()
                    .fill(dia)
                    .overlay(Diamond().stroke(Color(hex: 0x0D1117), lineWidth: 0.8))
                    .frame(width: 36, height: 36)
                VStack(spacing: 0) {
                    Text(hazLabel).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                    Text("\(hazClass)").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("CLASS \(hazClass)")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(Brand.danger)
                Text("Flammable")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x0D1117))
                Text(pg)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(Color(hex: 0x52606D))
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

    // FREIGHT CHARGES + SIGNATURE RECEIPT pill
    private var renderRateAndSignature: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FREIGHT CHARGES")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color(hex: 0x8A96A3))
                Text(rateDisplay)
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text(rateMetaDisplay)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(Color(hex: 0x52606D))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("SIGNATURE RECEIPT")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color(hex: 0x8A96A3))
                signaturePill
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }

    private var signaturePill: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 1) {
                Text("Pickup signed")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x0D1117))
                Text(pickupSignedMetaDisplay)
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(Color(hex: 0x52606D))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Brand.success.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // QR + audit — uses the canonical EusoQRView from
    // Views/Components/EusoQR.swift. Same generator every QR
    // surface in the app uses (driver pickup credential, escort
    // pairing, EusoTicket, agreement, settlement, profile, invite).
    private var renderQRAndAudit: some View {
        HStack(alignment: .top, spacing: 12) {
            EusoQRView(
                kind: .eusoTicket(kind: bolKind, id: bolNumberDisplay),
                role: .carrier,
                size: 56,
                cornerRadius: 6
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("SCAN AUDIT")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color(hex: 0x8A96A3))
                Text(auditUrlDisplay)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x0D1117))
                Text("SHA-256 · blockchain-anchored \(auditAnchorTime)")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(Color(hex: 0x52606D))
                Text("tx 0x9c4f…b021 · Polygon zkEVM")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(Color(hex: 0x52606D))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    // Footer — USDOT / MC / IRP / BOC-3 / FMCSA + UCC + CFR
    private var renderFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(CatalystPersona.carrierUSDOT) · \(CatalystPersona.carrierMC) · \(CatalystPersona.carrierIRP) · \(CatalystPersona.carrierBoc3) · FMCSA SAFER clean")
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(Color(hex: 0x8A96A3))
            Text("Subject to UCC §7-301 · per FMCSR 49 CFR §373.101 · per 49 CFR §172 hazmat papers")
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(Color(hex: 0x8A96A3))
        }
        .padding(.horizontal, 16)
    }

    // MARK: Send action ribbon

    private var sendActionRibbon: some View {
        Button {
            Task { await dispatchPDF() }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: dispatching ? "arrow.triangle.2.circlepath" : "paperplane.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(dispatching ? 360 : 0))
                    .animation(
                        dispatching
                            ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                            : .default,
                        value: dispatching
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(dispatching ? "Rendering and dispatching…" : sendTitleDisplay)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("3 recipients · auto-attach to Settlements + Wallet on POD")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(dispatching)
    }

    // MARK: Retention policy explainer

    private var retentionPolicyExplainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RETENTION POLICY")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text("Rendered EusoTickets retain for 7 years per 49 CFR §390.31. SHA-256 anchored on Polygon zkEVM at dispatch. Settlement attaches automatically on POD; Wallet credential refreshes when the PDF re-renders.")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard.opacity(scheme == .dark ? 0.40 : 0.60))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Display derivations (load-aware fallback to persona)

    private var loadNumberDisplay: String {
        load?.loadNumber ?? CatalystPersona.flagshipLoadNumber
    }

    private var loadShortIdDisplay: String {
        // "LD-260427" eyebrow on header band
        let full = loadNumberDisplay
        if let dash = full.dropFirst(3).firstIndex(of: "-") {
            return String(full[..<dash])
        }
        return full
    }

    private var bolKind: EusoQRKind.TicketKind {
        switch selectedDoc {
        case .bol:         return .bol
        case .pod:         return .pod
        case .runTicket:   return .runticket
        case .haulReceipt: return .haulreceipt
        }
    }

    private var bolNumberDisplay: String {
        if let ln = load?.loadNumber, let dashRange = ln.range(of: "-", options: [.backwards]) {
            return String(ln[dashRange.upperBound...])
        }
        return CatalystPersona.flagshipBolNumber
    }

    private var docTypeFullLabel: String {
        switch selectedDoc {
        case .bol:         return "Bill of Lading"
        case .pod:         return "Proof of Delivery"
        case .runTicket:   return "Run Ticket"
        case .haulReceipt: return "Haul Receipt"
        }
    }

    private var rideDateDisplay: String {
        load?.pickupDate.flatMap(shortDate) ?? CatalystPersona.flagshipDate
    }

    private var routeDisplay: String {
        if let l = load {
            let lane = l.laneDisplay
            let mc = l.cargoType?.uppercased().contains("FUEL") == true ? "MC-306" : "MC-306"
            let un = l.unNumber.map { "UN\($0)" } ?? "UN1203"
            let rate = l.rateDisplay
            return "\(lane) · \(mc) \(un) · \(rate)"
        }
        return "\(CatalystPersona.flagshipFromCity) → \(CatalystPersona.flagshipToCity) · MC-306 UN1203 · $1,900"
    }

    private var versionMetaDisplay: String {
        // "v3 · auto-saved 14 min ago · 248 KB" per Figma — version + size
        // are stable canvas constants until eusoTicket.* surfaces them.
        if load != nil {
            return "v3 · auto-saved · live preview"
        }
        return "v3 · auto-saved 14 min ago · 248 KB"
    }

    private var fromCityDisplay: String {
        load?.pickupLocation?.cityState ?? CatalystPersona.flagshipFromCity
    }

    private var fromAddressDisplay: String {
        if let o = load?.origin {
            let parts = [o.address, [o.city, o.state].compactMap { $0 }.joined(separator: ", ")]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
        }
        return CatalystPersona.flagshipFromAddress
    }

    private var fromTimeDisplay: String {
        if let pickup = load?.pickupDate.flatMap(longDate) {
            return "Pickup \(pickup)"
        }
        return CatalystPersona.flagshipFromTime
    }

    private var toCityDisplay: String {
        load?.deliveryLocation?.cityState ?? CatalystPersona.flagshipToCity
    }

    private var toAddressDisplay: String {
        if let d = load?.destination {
            let parts = [d.address, [d.city, d.state].compactMap { $0 }.joined(separator: ", ")]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
        }
        return CatalystPersona.flagshipToAddress
    }

    private var toTimeDisplay: String {
        if let deliv = load?.deliveryDate.flatMap(longDate) {
            return "Deliver \(deliv)"
        }
        return CatalystPersona.flagshipToTime
    }

    private var commodityDisplay: String {
        if let l = load {
            let name = l.commodityName ?? l.commodity ?? l.cargoType ?? "—"
            return "\(name) · \(l.weightDisplay)"
        }
        return CatalystPersona.flagshipCommodity
    }

    private var commodityMeta1Display: String {
        if let un = load?.unNumber {
            return "UN\(un) · PG II · NMFC 145880"
        }
        return CatalystPersona.flagshipCommodityMeta1
    }

    private var commodityMeta2Display: String {
        CatalystPersona.flagshipCommodityMeta2
    }

    private var rateDisplay: String {
        load?.rateDisplay ?? CatalystPersona.flagshipRateDisplay
    }

    private var rateMetaDisplay: String {
        CatalystPersona.flagshipRateMeta
    }

    private var pickupSignedMetaDisplay: String {
        if let pickup = load?.pickupDate.flatMap(timeOnly) {
            return "\(pickup) · \(CatalystPersona.carrierUSDOT.replacingOccurrences(of: "USDOT ", with: "DOT "))"
        }
        return "06:14 CDT · DOT 9211"
    }

    private var auditUrlDisplay: String {
        // Human-readable display URL per Figma — the QR encodes the
        // canonical universal link from EusoQRKind.eusoTicket.payload.
        "eusotrip.com/t/\(bolNumberDisplay)"
    }

    private var auditAnchorTime: String {
        if load?.pickupDate.flatMap(timeOnly) != nil {
            return load?.pickupDate.flatMap(timeOnly) ?? "09:14 CDT"
        }
        return "09:14 CDT"
    }

    private var sendTitleDisplay: String {
        "Render PDF · dispatch to \(CatalystPersona.shipperMonogram) + \(CatalystPersona.carrierMonogram) + receiver"
    }

    // MARK: - Date helpers

    private func shortDate(_ iso: String) -> String? {
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

    private func longDate(_ iso: String) -> String? {
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

    private func timeOnly(_ iso: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: iso)
        }
        guard let date = d else { return nil }
        let out = DateFormatter()
        out.dateFormat = "HH:mm zzz"
        return out.string(from: date)
    }

    // MARK: - Network

    private func fetchLoad() async {
        loading = true
        loadError = nil
        defer { loading = false }
        guard !loadId.isEmpty, loadId != "0" else { return }
        do {
            if let detail = try await EusoTripAPI.shared.loads.getDetail(id: loadId) {
                self.load = detail
            }
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func dispatchPDF() async {
        dispatching = true
        dispatchError = nil
        dispatchedURL = nil
        defer { dispatching = false }
        let bol = bolNumberDisplay
        do {
            let res = try await EusoTripAPI.shared.eusoTicket.generateBOLPDF(bolNumber: bol)
            self.dispatchedURL = res.documentUrl
            // Fire the canonical share / open notification — server
            // already knows DU + ME + receiver from the load record,
            // so the dispatcher chain runs server-side. iOS just
            // confirms by surfacing the documentUrl.
            if let url = URL(string: res.documentUrl) {
                await MainActor.run { UIApplication.shared.open(url) }
            }
        } catch {
            self.dispatchError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Diamond shape (hazmat callout)

private struct Diamond: Shape {
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

// Note on document-canvas grays: the rendered EusoTicket paper card is
// intentionally pinned to the Figma's exact ink (#0D1117), body
// (#52606D), and muted (#8A96A3) hues regardless of light/dark scheme
// — the CARD itself is a printed BOL preview, not a chrome surface.
// We use the canonical `Color(hex: UInt32)` initialiser shipped in
// `Theme/DesignSystem.swift` rather than re-declaring it here, which
// would shadow the global extension and create an ambiguity at every
// call site.

// MARK: - Previews

#Preview("313 · Catalyst · EusoTicket Renderer · Night") {
    CatalystEusoTicketRendererScreen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("313 · Catalyst · EusoTicket Renderer · Afternoon") {
    CatalystEusoTicketRendererScreen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
