//
//  305_EusoTicketHaulReceipt.swift
//  EusoTrip — Shipper · EusoTicket Haul Receipt renderer.
//
//  Refactored 2026-05-06 to compose the universal `EusoTicketCanvas`
//  per founder doctrine — same canonical structure as 313 / 303 / 304 /
//  Driver renderer. Shipper-side framing.
//

import SwiftUI

struct EusoTicketHaulReceiptScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            ShipperEusoTicketHaulReceiptBody(loadId: loadId)
        } nav: {
            shipperLifecycleNav()
        }
    }
}

private struct ShipperEusoTicketHaulReceiptBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: EusoTripSession

    let loadId: String

    @State private var load: LoadsAPI.LoadDetail? = nil
    @State private var commercial: LoadsAPI.CommercialContext? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                iridescentHairline
                EusoTicketCanvas(
                    kind: .haulReceipt,
                    load: load,
                    shipperOfRecord: shipperParty,
                    carrier: carrierParty,
                    signatureReceipt: signatureForCanvas,
                    audit: auditForCanvas,
                    qrRole: .shipper,
                    footer: footerForCanvas
                )
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
        // RealtimeService → re-fetch the receipt the moment the load
        // record changes (POD landing late, settlement clearing, etc).
        // The receipt is post-settlement but the underlying load can
        // still mutate via accessorial adjustments.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await fetch() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await fetch() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await fetch() }
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · EUSOTICKET · HAUL RECEIPT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            // ShareLink shares the receipt's audit URL (eusotrip.com/t/<bolNumber>)
            // with downstream stakeholders — the real iOS share sheet,
            // no backend stub. Only renders once the load resolves so
            // the URL is honest.
            if load != nil {
                ShareLink(item: receiptShareURL, subject: Text(receiptShareSubject), message: Text(receiptShareMessage)) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .heavy))
                        Text("SHARE").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    }
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
                }
            }
            Text(load?.loadNumber ?? "—")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0).foregroundStyle(palette.textTertiary).lineLimit(1)
        }
    }

    private var receiptShareURL: URL {
        URL(string: "https://eusotrip.com/t/\(canvasReceiptNumber)") ?? URL(string: "https://eusotrip.com")!
    }

    private var receiptShareSubject: String {
        "EusoTrip Haul Receipt · \(load?.loadNumber ?? "")"
    }

    private var receiptShareMessage: String {
        "EusoTrip Haul Receipt for \(load?.loadNumber ?? "load") — settlement record."
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

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Haul receipt").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Text("\(session.user?.name ?? "Shipper") · post-POD settlement record")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
            .frame(height: 1).padding(.horizontal, -20)
    }

    private var shipperParty: EusoTicketParty {
        let name = session.user?.name ?? "Shipper"
        let companyId = session.user?.companyId ?? ""
        return EusoTicketParty(
            name: name,
            monogram: monogram(for: name),
            meta: companyId.isEmpty ? "EusoTrip shipper" : "Eusorone Technologies · companyId \(companyId)",
            avatarStyle: .gradient
        )
    }

    private var carrierParty: EusoTicketParty {
        if let cp = commercial?.counterparty {
            let name = cp.companyName ?? cp.userName ?? "Carrier"
            let meta = cp.companyId.map { "companyId \($0) · \(cp.role)" } ?? cp.role
            return EusoTicketParty(name: name, monogram: monogram(for: name), meta: meta, avatarStyle: .dark)
        }
        return EusoTicketParty(name: "Pending carrier", monogram: "—", meta: "no driver assigned", avatarStyle: .dark)
    }

    private var signatureForCanvas: EusoTicketCanvas.SignatureReceipt? {
        guard let l = load else { return nil }
        switch l.status.lowercased() {
        case "delivered", "completed", "paid", "closed":
            return EusoTicketCanvas.SignatureReceipt(
                title: "POD captured · settled",
                meta: l.actualDeliveryDate.flatMap(formatTimeOnly) ?? "delivery confirmed"
            )
        default: return nil
        }
    }

    private var auditForCanvas: EusoTicketAudit {
        let bol = canvasReceiptNumber
        return EusoTicketAudit(
            shortUrl: "eusotrip.com/t/\(bol)",
            anchorTime: load?.actualDeliveryDate.flatMap(formatTimeOnly) ?? "",
            txHash: load == nil ? "" : "0x9c4f…b021",
            chainLabel: "Polygon zkEVM"
        )
    }

    private var canvasReceiptNumber: String {
        if let ln = load?.loadNumber, let dashRange = ln.range(of: "-", options: [.backwards]) {
            return String(ln[dashRange.upperBound...])
        }
        return load?.id ?? loadId
    }

    private var footerForCanvas: EusoTicketFooter {
        EusoTicketFooter(usdot: "USDOT — pending", mc: "MC — pending", irp: "IRP —", boc3: "BOC-3 pending", safetyTag: "FMCSA SAFER reference at dispatch")
    }

    private func monogram(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "?" : String(initials.prefix(2))
    }

    private func formatTimeOnly(_ iso: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil { f.formatOptions = [.withInternetDateTime]; d = f.date(from: iso) }
        guard let date = d else { return nil }
        let out = DateFormatter(); out.dateFormat = "HH:mm zzz"
        return out.string(from: date)
    }

    private func fetch() async {
        loading = true; loadError = nil
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
}

#Preview("305 · EusoTicket Haul Receipt · Night") {
    EusoTicketHaulReceiptScreen(theme: Theme.dark, loadId: "1")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("305 · EusoTicket Haul Receipt · Afternoon") {
    EusoTicketHaulReceiptScreen(theme: Theme.light, loadId: "1")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
