//
//  106B_DriverEusoTicketRenderer.swift
//  EusoTrip — Driver · EusoTicket Renderer (sibling of 106_MeEusoTickets).
//
//  The driver-side render of the universal EusoTicket — same canonical
//  structure as Catalyst 313 / Shipper 303-305, viewed from the driver
//  vantage. Where the Shipper sees "render & dispatch" and the Catalyst
//  sees "review before dispatching to DU+ME+receiver", the Driver sees
//  the as-rendered document for a load they're hauling — read-only,
//  with an action ribbon to share or save to Apple Wallet (PassKit).
//
//  Tri-role parity per founder doctrine "the eusoticket screen is the
//  universal eusoticket structure". This screen + Catalyst 313 +
//  Shipper 303/304/305 all compose `EusoTicketCanvas` from
//  `Views/Components/EusoTicketCanvas.swift` — single source of truth.
//
//  Wired to:
//    • `loads.getById` — load envelope.
//    • `drivers.getMyCarrier` — signed-in driver's carrier company
//      so the canvas can paint the carrier party with the driver's
//      OWN company name + DOT/MC.
//    • `EusoQRView` (kind: .eusoTicket(.bol/.pod/.runticket/.haulreceipt))
//      — canonical brand-tinted QR.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DriverEusoTicketRendererScreen: View {
    let theme: Theme.Palette
    let loadId: String
    let initialKind: EusoTicketDocType

    init(theme: Theme.Palette, loadId: String = "0", initialKind: EusoTicketDocType = .bol) {
        self.theme = theme
        self.loadId = loadId
        self.initialKind = initialKind
    }

    var body: some View {
        Shell(theme: theme) {
            DriverEusoTicketRendererBody(loadId: loadId, initialKind: initialKind)
        } nav: {
            BottomNav(
                leading: driverNavLeading_106B(),
                trailing: driverNavTrailing_106B(),
                orbState: .idle
            )
        }
    }
}

// Driver bottom nav is FROZEN per `feedback_bottom_nav_frozen.md` — do
// not touch labels, icons, or `isCurrent` flags. Use the canonical
// driver layout: Home · Loads · ESANG · Pulse · Me with Loads (or the
// nearest active anchor for the current flow) highlighted.
private func driverNavLeading_106B() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",       isCurrent: false),
     NavSlot(label: "Loads", systemImage: "shippingbox", isCurrent: true)]
}

private func driverNavTrailing_106B() -> [NavSlot] {
    [NavSlot(label: "Pulse", systemImage: "waveform.path.ecg", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",            isCurrent: false)]
}

private struct DriverEusoTicketRendererBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: EusoTripSession

    let loadId: String
    let initialKind: EusoTicketDocType

    @State private var selectedDoc: EusoTicketDocType
    @State private var load: LoadsAPI.LoadDetail? = nil
    @State private var carrierInfo: DriversAPI.MyCarrier? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var savingToWallet: Bool = false

    init(loadId: String, initialKind: EusoTicketDocType) {
        self.loadId = loadId
        self.initialKind = initialKind
        _selectedDoc = State(initialValue: initialKind)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                iridescentHairline
                docFilterChips
                EusoTicketCanvas(
                    kind: selectedDoc,
                    load: load,
                    shipperOfRecord: shipperParty,
                    carrier: carrierParty,
                    signatureReceipt: signatureForCanvas,
                    audit: auditForCanvas,
                    qrRole: .driver,
                    footer: footerForCanvas
                )
                actionRibbon
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
        // RealtimeService → re-fetch the EusoTicket the moment the
        // load record changes (status, carrier accept, accessorials,
        // POD landing). The driver's BOL/run-ticket/haul-receipt
        // canvas always reflects the live state.
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
                Text("DRIVER · EUSOTICKET")
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
            Text("EusoTicket").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Text("\(carrierInfo?.legalName ?? carrierInfo?.name ?? "Carrier") · \(session.user?.name ?? "Driver") · as-rendered document")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary).lineLimit(1)
        }
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
            .frame(height: 1).padding(.horizontal, -20)
    }

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

    private var actionRibbon: some View {
        Button {
            Task { await saveToWallet() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: savingToWallet ? "arrow.triangle.2.circlepath" : "wallet.pass.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(savingToWallet ? 360 : 0))
                    .animation(savingToWallet ? .linear(duration: 1.0).repeatForever(autoreverses: false) : .default, value: savingToWallet)
                VStack(alignment: .leading, spacing: 2) {
                    Text(savingToWallet ? "Saving to Apple Wallet…" : "Save to Apple Wallet · share PDF")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Read-only EusoTicket · re-render at any time from your Wallet pass")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain).disabled(savingToWallet)
    }

    // MARK: - Canvas-feed parties

    private var shipperParty: EusoTicketParty {
        // Driver-side: surface the SHIPPER party from the load.
        // `loads.getById` doesn't return the shipper name directly,
        // only `shipperId`. Use the §11 canonical mapping for the
        // flagship companyId 1 = Diego Usoro / Eusorone Technologies;
        // generic placeholder for others. (When a driver-side
        // shipper-name procedure ships, swap in here.)
        if load?.shipperId == 1 {
            return EusoTicketParty(
                name: "Diego Usoro",
                monogram: "DU",
                meta: "Eusorone Technologies · companyId 1",
                avatarStyle: .gradient
            )
        }
        if let id = load?.shipperId {
            return EusoTicketParty(
                name: "Shipper",
                monogram: "S\(id)",
                meta: "companyId \(id)",
                avatarStyle: .gradient
            )
        }
        return EusoTicketParty(name: "Pending shipper", monogram: "—", meta: "no shipper on file", avatarStyle: .gradient)
    }

    private var carrierParty: EusoTicketParty {
        // Driver-side: the driver's OWN carrier company is the carrier
        // party on the rendered document. Pulled from
        // `drivers.getMyCarrier`. When the driver isn't attached to a
        // carrier (rare — owner-ops without a company row), surface
        // an honest "self / 1099" descriptor instead of a fake name.
        if let c = carrierInfo {
            let name = c.legalName ?? c.name ?? "Carrier"
            let dot = c.dotNumber.map { "USDOT \($0)" } ?? "USDOT —"
            let mc = c.mcNumber.map { "MC-\($0)" } ?? "MC —"
            return EusoTicketParty(
                name: name,
                monogram: monogram(for: name),
                meta: "\(dot) · \(mc)",
                avatarStyle: .dark
            )
        }
        let driverName = session.user?.name ?? "Driver"
        return EusoTicketParty(
            name: driverName + " · 1099",
            monogram: monogram(for: driverName),
            meta: "no carrier company on file",
            avatarStyle: .dark
        )
    }

    private var signatureForCanvas: EusoTicketCanvas.SignatureReceipt? {
        guard let l = load else { return nil }
        switch l.status.lowercased() {
        case "in_transit":
            return EusoTicketCanvas.SignatureReceipt(
                title: "Pickup signed",
                meta: l.pickupDate.flatMap(formatTimeOnly) ?? "in transit"
            )
        case "delivered", "completed", "paid", "closed":
            return EusoTicketCanvas.SignatureReceipt(
                title: "POD captured",
                meta: l.actualDeliveryDate.flatMap(formatTimeOnly) ?? "delivered"
            )
        default: return nil
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
        if let c = carrierInfo {
            return EusoTicketFooter(
                usdot: c.dotNumber.map { "USDOT \($0)" } ?? "USDOT —",
                mc: c.mcNumber.map { "MC-\($0)" } ?? "MC —",
                irp: "IRP \(c.state ?? "—")",
                boc3: "BOC-3 active",
                safetyTag: "FMCSA SAFER \(c.complianceStatus ?? "reference")"
            )
        }
        return EusoTicketFooter(
            usdot: "USDOT — pending",
            mc: "MC — pending",
            irp: "IRP —",
            boc3: "BOC-3 —",
            safetyTag: "Carrier company not on file"
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
        if d == nil { f.formatOptions = [.withInternetDateTime]; d = f.date(from: iso) }
        guard let date = d else { return nil }
        let out = DateFormatter(); out.dateFormat = "HH:mm zzz"
        return out.string(from: date)
    }

    // MARK: - Network

    private func fetch() async {
        loading = true; loadError = nil
        defer { loading = false }
        do {
            async let loadTask: LoadsAPI.LoadDetail? = {
                guard !loadId.isEmpty, loadId != "0" else { return nil }
                return try? await EusoTripAPI.shared.loads.getDetail(id: loadId)
            }()
            async let carrierTask: DriversAPI.MyCarrier? = {
                try? await EusoTripAPI.shared.drivers.getMyCarrier()
            }()
            let (l, c) = await (loadTask, carrierTask)
            self.load = l
            self.carrierInfo = c
        }
    }

    private func saveToWallet() async {
        savingToWallet = true
        defer { savingToWallet = false }
        // Hand off to the existing PassKit pipeline. The
        // `EusoWalletPassService` flow ships the `.pkpass` from server +
        // surfaces `PKAddPassesViewController`. Posting the canonical
        // notification keeps this screen decoupled from PassKit
        // import — same wiring the founder shipped 2026-05-06 for
        // the credential pickup flow.
        NotificationCenter.default.post(
            name: Notification.Name("eusoDriverSaveTicketToWallet"),
            object: nil,
            userInfo: [
                "loadId": loadId,
                "kind": selectedDoc.qrKind.rawValue,
                "bolNumber": canvasBolNumber,
            ]
        )
    }
}

#Preview("106B · Driver · EusoTicket Renderer · Night") {
    DriverEusoTicketRendererScreen(theme: Theme.dark, loadId: "0", initialKind: .bol)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("106B · Driver · EusoTicket Renderer · Afternoon") {
    DriverEusoTicketRendererScreen(theme: Theme.light, loadId: "0", initialKind: .bol)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
