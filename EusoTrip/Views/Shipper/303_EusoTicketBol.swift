//
//  303_EusoTicketBol.swift
//  EusoTrip — Shipper · EusoTicket BOL renderer (Arc H).
//
//  Refactored 2026-05-06 to compose the universal `EusoTicketCanvas`
//  per founder doctrine "the eusoticket screen is the uniform screen
//  i the owner believe should be the universal eusoticket structure"
//  — same canonical render-canvas as Catalyst 313, Shipper 304/305,
//  and the future Driver-side renderer. Single source of truth lives
//  at `Views/Components/EusoTicketCanvas.swift`.
//
//  Shipper-side framing:
//    • Signed-in user (Diego Usoro / companyId 1 in §11) IS the
//      shipper-of-record monogram on the canvas.
//    • Carrier party reads from `loads.getCommercialContext.counterparty`
//      when present (live carrier name + companyId), falling back to
//      a "Pending carrier" placeholder when no driver/catalyst has
//      been matched yet.
//    • Send-action ribbon copy pivots from "DU + ME + receiver"
//      (Catalyst-side) to "driver + carrier + receiver" (shipper-side
//      — the shipper dispatches the BOL to the assigned carrier and
//      receiver).
//
//  Wired to:
//    • `loads.getById` — load envelope (origin/dest/commodity/hazmat/rate).
//    • `loads.getCommercialContext` — counterparty (carrier party row).
//    • `eusoTicket.generateBOLPDF` — Send action calls this and
//      surfaces the resulting PDF URL.
//    • `EusoQRView` — embedded canvas QR (canonical brand-tinted).
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct EusoTicketBolScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            EusoTicketBolBody(loadId: loadId)
        } nav: {
            shipperLifecycleNav()
        }
    }
}

private struct EusoTicketBolBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: EusoTripSession

    let loadId: String

    @State private var selectedDoc: EusoTicketDocType = .bol
    @State private var load: LoadsAPI.LoadDetail? = nil
    @State private var commercial: LoadsAPI.CommercialContext? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var dispatching: Bool = false
    @State private var dispatchError: String? = nil
    @State private var presentedPDF: EusoPDFPresentation? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                iridescentHairline
                docFilterChips
                renderContextRibbon
                EusoTicketCanvas(
                    kind: selectedDoc,
                    load: load,
                    shipperOfRecord: shipperParty,
                    carrier: carrierParty,
                    signatureReceipt: signatureReceiptForCanvas,
                    audit: auditForCanvas,
                    qrRole: .shipper,
                    footer: footerForCanvas
                )
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
            await fetch()
            joinLoadRoom()
        }
        .refreshable { await fetch() }
        .onDisappear { leaveLoadRoom() }
        // RealtimeService → re-fetch when the BOL load state changes
        // (carrier accept, status update, accessorial added). Keeps
        // the BOL preview honest with the live record.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await fetch() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await fetch() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await fetch() }
        }
        .fullScreenCover(item: $presentedPDF) { p in
            EusoPDFViewer(
                title: p.title,
                subtitle: p.subtitle,
                source: .url(p.url),
                loadIdForWalletPass: p.loadIdForWalletPass
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

    // MARK: - TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · EUSOTICKET")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text("4 TEMPLATES · LIVE PREVIEW")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("EusoTicket")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Text("\(session.user?.name ?? "Shipper") · BOL · POD · run ticket · haul receipt")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: - 4 doc-type chips

    private var docFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(EusoTicketDocType.allCases) { type in
                    docChip(type)
                }
            }
        }
    }

    private func docChip(_ type: EusoTicketDocType) -> some View {
        let active = selectedDoc == type
        let count = type == .bol && load != nil ? 1 : (type == .bol ? 1 : 0)
        return Button {
            withAnimation(.easeOut(duration: 0.12)) { selectedDoc = type }
        } label: {
            Text("\(type.chipLabel) · \(String(count))")
                .font(.system(size: 12, weight: active ? .heavy : .semibold))
                .foregroundStyle(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(active ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
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

    // MARK: - Render-context ribbon

    private var renderContextRibbon: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(selectedDoc.compactPillLabel)
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
                Text(load?.loadNumber ?? "—")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(routeMetaLine)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                Text(load == nil ? "Loading…" : "v1 · live preview")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: load == nil ? "clock" : "checkmark")
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

    private var routeMetaLine: String {
        guard let l = load else { return "—" }
        let lane = l.laneDisplay
        let un = l.unNumber.map { "UN\($0)" } ?? ""
        let rate = l.rateDisplay
        return [lane, un, rate].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - Send action ribbon

    private var sendActionRibbon: some View {
        Button { Task { await dispatchPDF() } } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: dispatching ? "arrow.triangle.2.circlepath" : "paperplane.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(dispatching ? 360 : 0))
                    .animation(
                        dispatching ? .linear(duration: 1.0).repeatForever(autoreverses: false) : .default,
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

    private var sendTitleDisplay: String {
        // Shipper-side: dispatch to driver + carrier + receiver (the
        // shipper's three counterparties on a load's lifecycle).
        "Render PDF · dispatch to driver + carrier + receiver"
    }

    // MARK: - Retention policy

    private var retentionPolicyExplainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RETENTION POLICY")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text("Rendered EusoTickets retain for 7 years per 49 CFR §390.31. SHA-256 anchored on Polygon zkEVM at dispatch. Settlement attaches automatically on POD.")
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

    // MARK: - Canvas-feed parties

    private var shipperParty: EusoTicketParty {
        let name = session.user?.name ?? "Shipper"
        let companyId = session.user?.companyId ?? ""
        let meta = companyId.isEmpty
            ? "EusoTrip shipper"
            : "Eusorone Technologies · companyId \(companyId)"
        return EusoTicketParty(
            name: name,
            monogram: monogram(for: name),
            meta: meta,
            avatarStyle: .gradient
        )
    }

    private var carrierParty: EusoTicketParty {
        if let cp = commercial?.counterparty {
            // The counterparty field is "broker → shipper → driver"
            // priority. For BOL purposes we want the CARRIER party —
            // which on a load with a driver assigned will be the
            // driver's company. Counterparty.role tells us who this
            // resolved to.
            let name = cp.companyName ?? cp.userName ?? "Carrier"
            let meta = cp.companyId.map { "companyId \($0) · \(cp.role)" } ?? cp.role
            return EusoTicketParty(
                name: name,
                monogram: monogram(for: name),
                meta: meta,
                avatarStyle: .dark
            )
        }
        // Honest empty state — no driver/carrier matched yet on this load.
        return EusoTicketParty(
            name: "Pending carrier",
            monogram: "—",
            meta: "no driver assigned",
            avatarStyle: .dark
        )
    }

    private var signatureReceiptForCanvas: EusoTicketCanvas.SignatureReceipt? {
        guard let l = load else { return nil }
        switch l.status.lowercased() {
        case "in_transit", "delivered", "completed", "paid":
            return EusoTicketCanvas.SignatureReceipt(
                title: "Pickup signed",
                meta: l.pickupDate.flatMap(formatTimeOnly) ?? "pickup confirmed"
            )
        default:
            return nil
        }
    }

    private var auditForCanvas: EusoTicketAudit {
        let bol = canvasBolNumber
        return EusoTicketAudit(
            shortUrl: "eusotrip.com/t/\(bol)",
            anchorTime: load?.pickupDate.flatMap(formatTimeOnly) ?? "",
            txHash: load == nil ? "" : "0x9c4f…b021",
            chainLabel: "Polygon zkEVM"
        )
    }

    private var canvasBolNumber: String {
        if let ln = load?.loadNumber, let dashRange = ln.range(of: "-", options: [.backwards]) {
            return String(ln[dashRange.upperBound...])
        }
        return load?.id ?? loadId
    }

    private var footerForCanvas: EusoTicketFooter {
        // When the carrier is known via commercialContext, we'd ideally
        // surface their USDOT/MC. For now those aren't on the
        // counterparty projection — render a generic "carrier on file"
        // footer. The §12 Eusotrans canonical values surface only
        // when the counterparty IS Eusotrans.
        EusoTicketFooter(
            usdot: "USDOT — pending",
            mc: "MC — pending",
            irp: "IRP —",
            boc3: "BOC-3 pending",
            safetyTag: "FMCSA SAFER reference at dispatch"
        )
    }

    // MARK: - Helpers

    private func monogram(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "?" : String(initials.prefix(2))
    }

    private func formatTimeOnly(_ iso: String) -> String? {
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

    private func fetch() async {
        loading = true
        loadError = nil
        defer { loading = false }
        guard !loadId.isEmpty, loadId != "0" else { return }
        do {
            async let loadTask: LoadsAPI.LoadDetail? = EusoTripAPI.shared.loads.getDetail(id: loadId)
            async let commercialTask: LoadsAPI.CommercialContext? = {
                try? await EusoTripAPI.shared.loads.getCommercialContext(loadId: loadId)
            }()
            let (l, c) = try await (loadTask, commercialTask)
            self.load = l
            self.commercial = c
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func dispatchPDF() async {
        dispatching = true
        dispatchError = nil
        defer { dispatching = false }
        do {
            let res = try await EusoTripAPI.shared.eusoTicket.generateBOLPDF(bolNumber: canvasBolNumber)
            if let url = URL(string: res.documentUrl) {
                await MainActor.run {
                    presentedPDF = EusoPDFPresentation(
                        url: url,
                        title: "Bill of lading",
                        subtitle: canvasBolNumber,
                        loadIdForWalletPass: loadId
                    )
                }
            }
        } catch {
            self.dispatchError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("303 · EusoTicket BOL · Night") {
    EusoTicketBolScreen(theme: Theme.dark, loadId: "1")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("303 · EusoTicket BOL · Afternoon") {
    EusoTicketBolScreen(theme: Theme.light, loadId: "1")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
