//
//  710_DispatchRunTicketCapture.swift
//  EusoTrip — Dispatch · Electronic run-ticket capture (EusoTicket mobile).
//
//  Mirrors Dispatch Commodity's electronic ticketing app — Android/iPad
//  ticket capture without proprietary hardware. Wired to runTickets.create
//  (issues RT-YYYY-XXXXXX numbers) and runTickets.list / getStats. Origin
//  and destination resolve automatically from loads.loadNumber so a
//  dispatcher can punch the load number, hand the phone to the driver,
//  and the ticket is on the wire before the truck leaves the gate.
//
//  2026-08-12 — this screen was called "capture" and had no camera, no
//  photo picker and no file importer: the only way to open a ticket was
//  to type a load number off a paper ticket the driver was holding at
//  the wellhead. It now scans that paper. The BYTES go to
//  `documentRouter.classifyAndRoute` (server-side Gemini vision); what
//  comes back is shown as SCANNED · UNCONFIRMED and fills nothing until
//  the dispatcher accepts it.
//
//  What accepting commits is stated on the card and is deliberately
//  narrow: `runTickets.create` takes `loadNumber` (+ optional loadId)
//  and NOTHING else, so the gauge / meter / API-gravity values the
//  reader pulls off the ticket are shown for the human to read and are
//  NOT written anywhere. Saying otherwise would be a fabricated
//  success, and those are regulated measurement fields.
//

import SwiftUI

struct DispatchRunTicketCaptureScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { TicketBody() } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
                orbState: .idle
            )
        }
    }
}

private struct RunTicketRow: Decodable, Identifiable, Hashable {
    let id: Int
    let ticketNumber: String
    let loadId: Int?
    let loadNumber: String?
    let status: String
    let origin: String?
    let destination: String?
    let totalMiles: Double?
    let totalFuel: Double?
    let totalTolls: Double?
    let totalExpenses: Double?
    let createdAt: String?
    // 2026-05-17 — Multi-modal payload. Run-ticket forms differ by
    // mode (truck miles + fuel + tolls vs vessel charter expenses vs
    // rail haulage); badge tells the dispatcher which expense column
    // set applies before they open the ticket.
    let transportMode: String?
    let multiVehicleCount: Int?
    let completedAt: String?
}

private struct RunTicketStats: Decodable, Hashable {
    let total: Int?
    let active: Int?
    let completed: Int?
    let pendingReview: Int?
    let totalFuel: Double?
    let totalTolls: Double?
    let totalExpenses: Double?
}

private struct TicketBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [RunTicketRow] = []
    @State private var stats: RunTicketStats? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var loadNumber: String = ""
    @State private var creating: Bool = false
    @State private var actionError: String? = nil
    @State private var lastCreated: String? = nil
    // Scan-to-open state.
    @State private var showScanner: Bool = false
    @State private var scanned: ClassifiedDocument? = nil
    /// Provenance for whatever is currently in `loadNumber`.
    @State private var scanProvenance: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = stats { statsGrid(s) }
                composeCard
                if let doc = scanned { scanReviewCard(doc) }
                if let m = lastCreated { LifecycleCard(accentGradient: true) { Text(m).font(EType.caption).foregroundStyle(palette.textPrimary) } }
                if let e = actionError { LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) } }
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .eusoRefreshable { await loadAll() }
        // Camera / photo library / file importer, all three routed to
        // the server-side reader. No on-device OCR.
        .sheet(isPresented: $showScanner) {
            DocumentClassifierSheet(
                mode: .prefillWizard,
                callerContext: "dispatch run-ticket capture — oilfield run ticket / EusoTicket, looking for the load or ticket number",
                onApplySingle: { doc in
                    scanned = doc
                    actionError = nil
                },
                onDispatchBatch: { _ in }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "ticket.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · EUSOTICKET").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Run-ticket capture").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Electronic ticketing, origin/destination auto-resolve from load number.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func statsGrid(_ s: RunTicketStats) -> some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "ACTIVE", value: "\(s.active ?? 0)", icon: "ticket")
            LifecycleStatTile(label: "REVIEW", value: "\(s.pendingReview ?? 0)", icon: "magnifyingglass", danger: (s.pendingReview ?? 0) > 0)
            LifecycleStatTile(label: "DONE",   value: "\(s.completed ?? 0)", icon: "checkmark.seal")
        }
    }

    private var composeCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "OPEN A TICKET", icon: "plus.app.fill")
            HStack(spacing: 8) {
                TextField("Load number (e.g. LD-260427-A38FB)", text: $loadNumber)
                    .textFieldStyle(.plain)
                    .font(EType.body)
                    .padding(10)
                    .background(palette.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                Button { Task { await create() } } label: {
                    HStack(spacing: 4) {
                        if creating { ProgressView().tint(.white) }
                        Text(creating ? "Opening…" : "Open").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain).disabled(creating || loadNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button { showScanner = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.viewfinder.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Scan the paper ticket")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                        Text("Photo, library or file. Reading needs a signal — it does not happen on this phone. The load number that comes back is a suggestion until you confirm it.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
            if let prov = scanProvenance {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Brand.warning).padding(.top, 2)
                    Text(prov)
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: — Scan review (SCANNED · UNCONFIRMED)

    /// Ticket-number-ish keys the classifier uses across the run-ticket
    /// and BOL shapes, most specific first. Whichever one is present is
    /// PROPOSED into the load-number field; if none is present we say so
    /// and leave the field alone rather than guessing from a partial.
    private static let loadNumberKeys = [
        "loadNumber", "loadNo", "ticketNumber", "runTicketNumber",
        "bolNumber", "referenceNumber", "orderNumber"
    ]

    /// Every field worth showing the dispatcher, in the order a run
    /// ticket is read. Absent keys are OMITTED — never rendered as an
    /// empty string or a zero.
    private func readFields(_ doc: ClassifiedDocument) -> [(label: String, value: String)] {
        let interesting: [(String, String)] = [
            ("loadNumber", "Load number"), ("loadNo", "Load number"),
            ("ticketNumber", "Ticket number"), ("runTicketNumber", "Ticket number"),
            ("bolNumber", "BOL number"), ("referenceNumber", "Reference"),
            ("orderNumber", "Order number"),
            ("leaseNumber", "Lease"), ("propertyNumber", "Property"),
            ("forAccountOf", "For account of"), ("carrier", "Carrier"),
            ("driverName", "Driver"), ("date", "Date"),
            ("openGauge", "Open gauge"), ("closeGauge", "Close gauge"),
            ("highGauge", "High gauge"), ("lowGauge", "Low gauge"),
            ("meterOff", "Meter off"), ("meterOn", "Meter on"),
            ("meterFactor", "Meter factor"), ("avgLineTemp", "Avg line temp"),
            ("apiGravity", "API gravity"), ("bsw", "BS&W"),
            ("grossBarrels", "Gross bbls"), ("netBarrels", "Net bbls"),
            ("tankCapacity", "Tank capacity"), ("tankHeight", "Tank height"),
            ("origin", "Origin"), ("destination", "Destination")
        ]
        var out: [(label: String, value: String)] = []
        var used = Set<String>()
        for (key, label) in interesting {
            guard !used.contains(label) else { continue }
            if let v = doc.fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                out.append((label: label, value: v))
                used.insert(label)
            }
        }
        return out
    }

    private func scannedLoadNumber(_ doc: ClassifiedDocument) -> String? {
        for k in Self.loadNumberKeys {
            if let v = doc.fields[k]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                return v
            }
        }
        return nil
    }

    @ViewBuilder
    private func scanReviewCard(_ doc: ClassifiedDocument) -> some View {
        let proposed = scannedLoadNumber(doc)
        ScannedFieldsReviewCard(
            title: "Run ticket read",
            detectedType: doc.classifiedType,
            confidence: doc.confidence,
            warnings: doc.warnings + (proposed == nil
                ? ["No load or ticket number was found on this document. Nothing will be filled in — type it from the paper."]
                : []),
            fields: readFields(doc),
            commitNote: proposed == nil
                ? "Accepting files nothing. Opening a ticket needs a load number, and the reader did not find one."
                : "Accepting puts \(proposed!) in the load-number field above. It does not open the ticket — you still tap Open. Everything else listed here is what the reader saw on the paper: EusoTicket stores the load number and resolves origin/destination from the load, so the gauge, meter and gravity readings above are NOT filed by this screen. Enter them on the ticket itself.",
            acceptTitle: proposed == nil ? "Nothing to accept" : "Use this load number",
            onAccept: {
                guard let n = proposed else { return }
                loadNumber = n
                scanProvenance = "Load number \(n) was read off a scanned document, not typed. Check it against the paper before you tap Open."
                scanned = nil
            },
            onDiscard: {
                scanned = nil
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading tickets…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty {
            EusoEmptyState(systemImage: "ticket", title: "No tickets yet", subtitle: "Punch a load number above to open the first one.")
        } else {
            ForEach(rows) { t in
                LifecycleCard(accentGradient: t.status == "active") {
                    HStack(spacing: 8) {
                        LifecycleSection(label: t.ticketNumber, icon: "ticket.fill")
                        Spacer(minLength: 0)
                        LoadModeBadge(modeRaw: t.transportMode,
                                      multiVehicleCount: t.multiVehicleCount,
                                      compact: true)
                    }
                    LifecycleRow(label: "Load",        value: dashIfEmpty(t.loadNumber))
                    LifecycleRow(label: "Origin",      value: dashIfEmpty(t.origin))
                    LifecycleRow(label: "Destination", value: dashIfEmpty(t.destination))
                    LifecycleRow(label: "Status",      value: t.status.uppercased())
                    LifecycleRow(label: "Miles",       value: t.totalMiles.map { String(format: "%.0f mi", $0) } ?? "-")
                    LifecycleRow(label: "Fuel",        value: usd(t.totalFuel))
                    LifecycleRow(label: "Tolls",       value: usd(t.totalTolls))
                    LifecycleRow(label: "Expenses",    value: usd(t.totalExpenses))
                    LifecycleRow(label: "Opened",      value: humanISO(t.createdAt))
                }
            }
        }
    }

    private func loadAll() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int }
        do {
            async let r: [RunTicketRow] = EusoTripAPI.shared.query("runTickets.list", input: In(limit: 100))
            async let s: RunTicketStats = EusoTripAPI.shared.queryNoInput("runTickets.getStats")
            let (rrows, sstats) = try await (r, s)
            rows = rrows
            stats = sstats
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func create() async {
        creating = true; actionError = nil
        struct In: Encodable { let loadNumber: String }
        struct Out: Decodable { let ticketNumber: String?; let id: Int? }
        do {
            let r: Out = try await EusoTripAPI.shared.mutation("runTickets.create", input: In(loadNumber: loadNumber))
            lastCreated = "Opened ticket \(r.ticketNumber ?? "-") for \(loadNumber)."
            loadNumber = ""
            scanProvenance = nil
            await loadAll()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        creating = false
    }
}

#Preview("710 · Run-ticket capture · Night") { DispatchRunTicketCaptureScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("710 · Run-ticket capture · Afternoon") { DispatchRunTicketCaptureScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }

