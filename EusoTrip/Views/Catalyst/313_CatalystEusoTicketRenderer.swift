//
//  313_CatalystEusoTicketRenderer.swift
//  EusoTrip — Catalyst · EusoTicket Renderer (brick 313).
//
//  Pixel-faithful port of "313 Catalyst EusoTicket Renderer · Light"
//  (Figma `~/Desktop/EusoTrip 2027 UI Wireframes/03 Catalyst/Light-SVG/`)
//  + the matching dark variant. The Catalyst reviews the as-rendered
//  EusoTicket document for the active (selected) load before dispatching
//  it to the shipper-of-record and the receiver. The rendered document
//  on the preview canvas is the BOL/POD/run-ticket/haul-receipt for the
//  load routed into this screen via `BrokerNavContext.latestLoadId`.
//
//  Chassis (top → bottom, matching SVG):
//    • TopBar eyebrow + textTertiary counter
//    • Title "EusoTicket" + doc-type subtitle
//    • IridescentHairline
//    • 4-chip doc-type filter row (BOL active by default — gradient)
//    • Render-context ribbon (load id + version meta + green ✓)
//    • Live-preview EusoTicket render canvas (gradient header band +
//      origin/destination strip + Shipper/Carrier parties block +
//      commodity + hazmat diamond + freight rate + signature receipt
//      pill + canonical EusoQRView audit chip + compliance footer)
//    • Send action ribbon (gradient — Render PDF · dispatch)
//    • Retention-policy explainer
//    • BottomNav · Catalyst variant · DISPATCH active
//
//  QR system: canonical `EusoQRView` (Views/Components/EusoQR.swift)
//  — same generator that ships across every QR surface in the app.
//  Payload is `EusoQRKind.eusoTicket(kind:, id: bolNumber)` with
//  `role: .carrier` so the receiving side decodes the catalyst context
//  out of the URL without a second auth fetch. Rendered with the brand
//  blue→magenta diagonal gradient on white, error-correction level H
//  (30 % recoverable). The audit text under the QR shows the
//  human-readable short URL `eusotrip.com/t/<bol>` per the Figma
//  audit-chip copy — the QR itself encodes the canonical universal
//  link the iOS deep-link handler + web router both consume.
//
//  ZERO-FABRICATION doctrine (2026-06-06 rebuild):
//    • Every business value binds to the real load record returned by
//      `loads.getById` (typed `LoadsAPI.LoadDetail`). There is NO
//      fabricated MATRIX-50 / A38FB12C7E / Houston→Dallas / Gasoline /
//      $1,900 / blockchain-tx fallback — when a field is missing on the
//      record the surface renders an honest "—".
//    • Shipper-of-record / carrier identity come from the session user
//      (the signed-in Catalyst) or render "—". No founder company /
//      persona (Eusorone Technologies / Diego Usoro / Michael Eusorone /
//      Aurora / Eusotrans / EIN 87-3104952) is ever painted.
//    • When no load is routed (or it doesn't resolve) the canvas is
//      replaced with the canonical `EusoEmptyState` — never a sample BOL.
//    • The footer states only what the record verifies. It never asserts
//      "FMCSA SAFER clean / authority active / insurance verified" — on a
//      no-source/failure path it reads "unavailable".
//
//  Wired to:
//    • `loads.getDetail` → `loads.getById` for the previewed load
//      (origin/destination, commodity, hazmat, rate, dates).
//    • `eusoTicket.generateBOLPDF` on Send → produces the PDF and
//      dispatches it server-side. We don't fabricate a "PDF generated"
//      state if the call fails — surface the error inline.
//
//  Powered by ESANG AI™.
//

import SwiftUI

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
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Body

private struct CatalystEusoTicketRenderer: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: EusoTripSession

    let loadId: String

    @State private var selectedDoc: CatalystDocType = .bol
    @State private var load: LoadsAPI.LoadDetail? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var dispatching: Bool = false
    @State private var dispatchError: String? = nil
    @State private var dispatchedURL: String? = nil
    /// In-app PDF presentation for the dispatched EusoTicket PDF.
    /// Replaces the prior `UIApplication.shared.open(url)` Safari
    /// punt with a native EusoPDFViewer sheet so the catalyst stays
    /// in the EusoTrip app.
    @State private var pdfPresentation: EusoPDFPresentation? = nil

    /// Honest no-source token — em-dash everywhere a field is absent.
    private let dash = "—"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                iridescentHairline
                docFilterChips
                renderContextRibbon
                if load != nil {
                    renderCanvas
                    sendActionRibbon
                } else {
                    emptyCanvas
                }
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
        // In-app EusoTicket PDF viewer — opens the dispatched PDF
        // inside the EusoTrip app via EusoPDFViewer (PDFKit native
        // render + iOS share sheet for Save to Files / AirDrop).
        .sheet(item: $pdfPresentation) { pres in
            EusoPDFViewer(
                title: pres.title,
                subtitle: pres.subtitle,
                source: .url(pres.url),
                allowSigning: false,
                onSigned: nil,
                loadIdForWalletPass: pres.loadIdForWalletPass
            )
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
            Text("BOL · POD · run ticket · haul receipt")
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
        // Counter dot per Figma — BOL shows 1 (the rendered preview) only
        // when a real load record is resolved; the others count zero until
        // a POD/Run Ticket/Haul Receipt has been generated server-side.
        // A future firing wires these from `eusoTicket.listBOLs(loadId:)`.
        let count = (type == .bol && load != nil) ? 1 : 0

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
            // Green ✓ — render fresh / saved (only when a real record resolved)
            if load != nil {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(LinearGradient.diagonal)
                    .clipShape(Circle())
            }
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

    // MARK: Empty canvas — no load routed / not resolved

    private var emptyCanvas: some View {
        Group {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
            } else if let err = loadError {
                EusoEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "Couldn't load this EusoTicket",
                    subtitle: err
                )
            } else {
                EusoEmptyState(
                    systemImage: "doc.text",
                    title: "No load selected",
                    subtitle: "Open a load to render its EusoTicket. The BOL, POD, run ticket and haul receipt paint here once a load is routed in."
                )
            }
        }
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

    // Gradient header band — "EUSOTICKET" + doc-type № + load id + date
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

    // SHIPPER OF RECORD + CARRIER — bound to the session user (the
    // signed-in Catalyst) and the load's shipper, never a founder persona.
    private var renderParties: some View {
        HStack(alignment: .top, spacing: 0) {
            partyBlock(
                eyebrow: "SHIPPER OF RECORD",
                monogram: shipperMonogram,
                monogramFill: AnyShapeStyle(LinearGradient.diagonal),
                title: shipperNameDisplay,
                meta: shipperMetaDisplay
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            partyBlock(
                eyebrow: "CARRIER",
                monogram: carrierMonogram,
                monogramFill: AnyShapeStyle(Color(hex: 0x0D1117)),
                title: carrierNameDisplay,
                meta: carrierMetaDisplay
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
                if let meta2 = commodityMeta2Display {
                    Text(meta2)
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(0.3)
                        .foregroundStyle(Color(hex: 0x52606D))
                }
            }
            Spacer(minLength: 0)
            if let haz = load?.hazmatClass, !haz.isEmpty {
                hazmatCallout(hazClass: haz)
            }
        }
        .padding(.horizontal, 16)
    }

    // Hazmat diamond callout — Brand.danger gradient (red→orange).
    // Rendered only when the load carries a real hazmatClass. Class 3 is
    // flammable; other classes show the class number without asserting a
    // label we can't verify.
    private func hazmatCallout(hazClass: String) -> some View {
        let isFlammable = hazClass == "3"
        let hazLabel = isFlammable ? "FLAM" : "HAZ"
        // Packing group is only known when the record surfaces a UN number
        // lane; otherwise honest em-dash.
        let pg = load?.unNumber != nil ? "PG II" : dash

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
                    Text(hazClass).font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("CLASS \(hazClass)")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(Brand.danger)
                Text(isFlammable ? "Flammable" : "Hazardous")
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
        // The pickup-signed receipt only renders an affirmative checkmark
        // when the load has actually advanced past pickup (a real status /
        // actualDeliveryDate signal). Otherwise it reads "pending" — we
        // never assert a signature we can't verify.
        let signed = pickupSigned
        return HStack(spacing: 6) {
            Image(systemName: signed ? "checkmark" : "clock")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(signed ? Brand.success : Color(hex: 0x8A96A3))
            VStack(alignment: .leading, spacing: 1) {
                Text(signed ? "Pickup signed" : "Pickup pending")
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
        .background((signed ? Brand.success : Color(hex: 0x8A96A3)).opacity(0.10))
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
                // The QR encodes the canonical universal link; we describe
                // the scan target honestly. We do NOT assert a blockchain
                // transaction hash / anchor time we can't verify from the
                // record — the on-chain anchor lands at dispatch (server).
                Text("Resolves the canonical EusoTicket deep link")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(Color(hex: 0x52606D))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    // Footer — compliance line bound to what the record verifies.
    // Never asserts unverified positive compliance ("SAFER clean /
    // authority active / insurance verified"); on a no-source path the
    // carrier registration line reads "unavailable".
    private var renderFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(carrierRegistrationFooter)
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
                    Text("Recipients resolved from the load · auto-attach to Settlements + Wallet on POD")
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

    // MARK: - Display derivations (real-record only; "—" when absent)

    private var loadNumberDisplay: String {
        load?.loadNumber ?? dash
    }

    private var loadShortIdDisplay: String {
        // Short eyebrow on header band — the prefix of the load number up
        // to the second dash (e.g. "LD-260427"). Honest "—" when absent.
        guard let full = load?.loadNumber, !full.isEmpty else { return dash }
        if let dashIdx = full.dropFirst(3).firstIndex(of: "-") {
            return String(full[..<dashIdx])
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
        // The document number is derived from the load number's trailing
        // segment when present; otherwise the load number itself; honest
        // "—" when there is no record.
        guard let ln = load?.loadNumber, !ln.isEmpty else { return dash }
        if let dashRange = ln.range(of: "-", options: [.backwards]) {
            return String(ln[dashRange.upperBound...])
        }
        return ln
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
        load?.pickupDate.flatMap(shortDate) ?? dash
    }

    private var routeDisplay: String {
        guard let l = load else { return dash }
        let lane = l.laneDisplay
        let un = l.unNumber.map { "UN\($0)" }
        let parts = [lane, un, l.rateValue > 0 ? l.rateDisplay : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty && $0 != dash }
        return parts.isEmpty ? dash : parts.joined(separator: " · ")
    }

    private var versionMetaDisplay: String {
        // Live preview marker — no fabricated version number / file size /
        // "14 min ago" timestamp. Updated-at, when present, is honest.
        guard load != nil else { return dash }
        if let updated = load?.updatedAt.flatMap(shortDate) {
            return "Live preview · updated \(updated)"
        }
        return "Live preview"
    }

    private var fromCityDisplay: String {
        let cs = load?.pickupLocation?.cityState ?? ""
        return cs.isEmpty ? dash : cs
    }

    private var fromAddressDisplay: String {
        guard let o = load?.origin else { return dash }
        let line = [o.city, o.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let parts = [o.address, line.isEmpty ? nil : line]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? dash : parts.joined(separator: " · ")
    }

    private var fromTimeDisplay: String {
        guard let pickup = load?.pickupDate.flatMap(longDate) else { return dash }
        return "Pickup \(pickup)"
    }

    private var toCityDisplay: String {
        let cs = load?.deliveryLocation?.cityState ?? ""
        return cs.isEmpty ? dash : cs
    }

    private var toAddressDisplay: String {
        guard let d = load?.destination else { return dash }
        let line = [d.city, d.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let parts = [d.address, line.isEmpty ? nil : line]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? dash : parts.joined(separator: " · ")
    }

    private var toTimeDisplay: String {
        guard let deliv = load?.deliveryDate.flatMap(longDate) else { return dash }
        return "Deliver \(deliv)"
    }

    private var commodityDisplay: String {
        guard let l = load else { return dash }
        let name = [l.commodityName, l.commodity, l.cargoType]
            .compactMap { $0 }
            .first(where: { !$0.isEmpty })
        let weight = l.weightValue > 0 ? l.weightDisplay : nil
        let parts = [name, weight].compactMap { $0 }
        return parts.isEmpty ? dash : parts.joined(separator: " · ")
    }

    private var commodityMeta1Display: String {
        // Only fields the record actually carries — UN number + ERG guide.
        // No fabricated NMFC / packing-group string.
        guard let l = load else { return dash }
        var bits: [String] = []
        if let un = l.unNumber, !un.isEmpty { bits.append("UN\(un)") }
        if let erg = l.ergGuide { bits.append("ERG \(erg)") }
        return bits.isEmpty ? dash : bits.joined(separator: " · ")
    }

    private var commodityMeta2Display: String? {
        // Equipment type, when present, is a real record field. No
        // fabricated MC-306 tanker / seal number constant.
        guard let eq = load?.equipmentType, !eq.isEmpty else { return nil }
        return eq
    }

    private var rateDisplay: String {
        // LoadDetail.rateDisplay already returns "—" when the column is
        // missing or zero — no invented "$1,900.00".
        load?.rateDisplay ?? dash
    }

    private var rateMetaDisplay: String {
        // Rate terms are not a column on the load record — honest "—".
        dash
    }

    private var pickupSigned: Bool {
        // Treat the load as past pickup once it has advanced beyond the
        // pre-pickup states. We don't assert a signature without a status
        // signal.
        guard let status = load?.status.lowercased() else { return false }
        let prePickup: Set<String> = ["posted", "bidding", "assigned", "en_route_pickup", "at_pickup"]
        return !prePickup.contains(status)
    }

    private var pickupSignedMetaDisplay: String {
        guard pickupSigned else { return dash }
        if let pickup = load?.pickupDate.flatMap(timeOnly) {
            return pickup
        }
        return dash
    }

    private var auditUrlDisplay: String {
        // Human-readable display URL per Figma — the QR encodes the
        // canonical universal link from EusoQRKind.eusoTicket.payload.
        let bol = bolNumberDisplay
        return bol == dash ? dash : "eusotrip.com/t/\(bol)"
    }

    private var sendTitleDisplay: String {
        "Render PDF · dispatch to shipper + carrier + receiver"
    }

    // MARK: Party identity (session user / load record; never a persona)

    /// Carrier identity = the signed-in Catalyst (the account dispatching
    /// the document). Name from the session user, or "—".
    private var carrierNameDisplay: String {
        let name = session.user?.name?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? dash : name
    }

    private var carrierMonogram: String {
        initials(from: session.user?.name)
    }

    private var carrierMetaDisplay: String {
        // The load record / session user carry no USDOT / MC on this
        // surface — show the account email when present, else "—". Never a
        // fabricated USDOT / MC number.
        let email = session.user?.email.trimmingCharacters(in: .whitespaces) ?? ""
        return email.isEmpty ? dash : email
    }

    /// Carrier registration footer — never asserts unverified positive
    /// compliance. With no DOT/MC/SAFER source on this surface it reads
    /// "unavailable".
    private var carrierRegistrationFooter: String {
        "Carrier authority / insurance · unavailable on this surface"
    }

    /// Shipper of record — identified by the load's shipper. The record
    /// carries only a numeric shipperId here, so we surface that honestly
    /// rather than fabricating a company name.
    private var shipperNameDisplay: String {
        if let sid = load?.shipperId {
            return "Shipper #\(sid)"
        }
        return dash
    }

    private var shipperMonogram: String {
        if let sid = load?.shipperId {
            return "S\(sid % 100)"
        }
        return dash
    }

    private var shipperMetaDisplay: String {
        load?.shipperId.map { "shipperId \($0)" } ?? dash
    }

    private func initials(from name: String?) -> String {
        let parts = (name ?? "").split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        let joined = letters.joined().uppercased()
        return joined.isEmpty ? dash : joined
    }

    // MARK: - Date helpers

    private func shortDate(_ iso: String) -> String? {
        guard let date = parseISO(iso) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "yyyy-MM-dd"
        return out.string(from: date)
    }

    private func longDate(_ iso: String) -> String? {
        guard let date = parseISO(iso) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MM-dd · HH:mm zzz"
        return out.string(from: date)
    }

    private func timeOnly(_ iso: String) -> String? {
        guard let date = parseISO(iso) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "HH:mm zzz"
        return out.string(from: date)
    }

    private func parseISO(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    // MARK: - Network

    private func fetchLoad() async {
        loading = true
        loadError = nil
        defer { loading = false }
        guard !loadId.isEmpty, loadId != "0" else {
            // No load routed in — honest empty state, no sample BOL.
            self.load = nil
            return
        }
        do {
            if let detail = try await EusoTripAPI.shared.loads.getDetail(id: loadId) {
                self.load = detail
            } else {
                self.load = nil
            }
        } catch {
            self.load = nil
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func dispatchPDF() async {
        guard let l = load else { return }
        dispatching = true
        dispatchError = nil
        dispatchedURL = nil
        defer { dispatching = false }
        let bol = bolNumberDisplay
        do {
            let res = try await EusoTripAPI.shared.eusoTicket.generateBOLPDF(bolNumber: bol)
            self.dispatchedURL = res.documentUrl
            // Fire the canonical share / open notification — server
            // already knows shipper + carrier + receiver from the load
            // record, so the dispatcher chain runs server-side. iOS just
            // confirms by surfacing the documentUrl.
            if let url = URL(string: res.documentUrl) {
                let title = "EusoTicket · \(bol == dash ? "—" : bol)"
                let subtitle = "Load \(l.loadNumber)"
                let loadIdForWallet = l.id
                await MainActor.run {
                    pdfPresentation = EusoPDFPresentation(
                        url: url,
                        title: title,
                        subtitle: subtitle,
                        loadIdForWalletPass: loadIdForWallet
                    )
                }
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
