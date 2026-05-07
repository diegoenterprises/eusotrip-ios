//
//  304_EusoTicketRunTicket.swift
//  EusoTrip — Shipper · EusoTicket Run Ticket renderer.
//
//  Refactored 2026-05-06 to compose the universal `EusoTicketCanvas`
//  per founder doctrine — same canonical structure as 313 / 303 / 305 /
//  Driver renderer. Shipper-side framing: signed-in shipper is the
//  shipper-of-record, carrier comes from `loads.getCommercialContext.
//  counterparty`.
//
//  Wired to `loads.getById` + `loads.getCommercialContext` +
//  `eusoTicket.generateRunTicketPDF` for the dispatch action.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct EusoTicketRunTicketScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            ShipperEusoTicketRunTicketBody(loadId: loadId)
        } nav: {
            shipperLifecycleNav()
        }
    }
}

private struct ShipperEusoTicketRunTicketBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: EusoTripSession

    let loadId: String

    @State private var load: LoadsAPI.LoadDetail? = nil
    @State private var commercial: LoadsAPI.CommercialContext? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var dispatching: Bool = false
    @State private var dispatchError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                iridescentHairline
                EusoTicketCanvas(
                    kind: .runTicket,
                    load: load,
                    shipperOfRecord: shipperParty,
                    carrier: carrierParty,
                    signatureReceipt: signatureForCanvas,
                    audit: auditForCanvas,
                    qrRole: .shipper,
                    footer: footerForCanvas
                )
                sendActionRibbon
                if let err = dispatchError {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger).padding(.horizontal, 4)
                }
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
        // RealtimeService → re-fetch when status / accessorials /
        // carrier change so the run ticket reflects what's actually
        // dispatched.
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

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · EUSOTICKET · RUN TICKET")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text(load?.loadNumber ?? "—")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0).foregroundStyle(palette.textTertiary).lineLimit(1)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Run ticket").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Text("\(session.user?.name ?? "Shipper") · per-haul measurement record")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
            .frame(height: 1).padding(.horizontal, -20)
    }

    private var sendActionRibbon: some View {
        Button { Task { await dispatchPDF() } } label: {
            HStack(spacing: 12) {
                Image(systemName: dispatching ? "arrow.triangle.2.circlepath" : "paperplane.fill")
                    .font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                    .rotationEffect(.degrees(dispatching ? 360 : 0))
                    .animation(dispatching ? .linear(duration: 1.0).repeatForever(autoreverses: false) : .default, value: dispatching)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dispatching ? "Rendering and dispatching…" : "Render PDF · file to settlement + carrier")
                        .font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    Text("Auto-attaches to load run · settles on POD acceptance")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain).disabled(dispatching)
    }

    // MARK: - Canvas-feed

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
        case "in_transit", "delivered", "completed", "paid":
            return EusoTicketCanvas.SignatureReceipt(
                title: "Loaded · meter sealed",
                meta: l.pickupDate.flatMap(formatTimeOnly) ?? "load confirmed"
            )
        default: return nil
        }
    }

    private var auditForCanvas: EusoTicketAudit {
        let bol = canvasTicketNumber
        return EusoTicketAudit(
            shortUrl: "eusotrip.com/t/\(bol)",
            anchorTime: load?.pickupDate.flatMap(formatTimeOnly) ?? "",
            txHash: load == nil ? "" : "0x9c4f…b021",
            chainLabel: "Polygon zkEVM"
        )
    }

    private var canvasTicketNumber: String {
        if let ln = load?.loadNumber, let dashRange = ln.range(of: "-", options: [.backwards]) {
            return String(ln[dashRange.upperBound...])
        }
        return load?.id ?? loadId
    }

    private var footerForCanvas: EusoTicketFooter {
        EusoTicketFooter(usdot: "USDOT — pending", mc: "MC — pending", irp: "IRP —", boc3: "BOC-3 pending", safetyTag: "FMCSA SAFER reference at dispatch")
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
        if d == nil { f.formatOptions = [.withInternetDateTime]; d = f.date(from: iso) }
        guard let date = d else { return nil }
        let out = DateFormatter(); out.dateFormat = "HH:mm zzz"
        return out.string(from: date)
    }

    // MARK: - Network

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

    private func dispatchPDF() async {
        dispatching = true; dispatchError = nil
        defer { dispatching = false }
        do {
            let res = try await EusoTripAPI.shared.eusoTicket.generateRunTicketPDF(ticketNumber: canvasTicketNumber)
            if let url = URL(string: res.documentUrl) {
                await MainActor.run { UIApplication.shared.open(url) }
            }
        } catch {
            self.dispatchError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("304 · EusoTicket Run Ticket · Night") {
    EusoTicketRunTicketScreen(theme: Theme.dark, loadId: "1")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("304 · EusoTicket Run Ticket · Afternoon") {
    EusoTicketRunTicketScreen(theme: Theme.light, loadId: "1")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
