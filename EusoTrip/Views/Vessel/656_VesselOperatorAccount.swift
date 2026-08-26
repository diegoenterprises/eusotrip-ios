//
//  656_VesselOperatorAccount.swift
//  EusoTrip — Vessel Operator · My Account (ME tab).
//
//  Verbatim port of "656 Vessel Operator Account.svg" (Light + Dark). Vessel
//  counterpart of 556_RailEngineerAccount. This is the GENUINE ME surface:
//  VesselOperatorNavController.swift maps "me" -> "Vesl656". Nav anchored to
//  VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME) ME current.
//
//  Data:
//    users.me            (EXISTS server/routers/users.ts:94)  -> identity
//    users.getProfile    (EXISTS users.ts:105)                -> contact/prefs
//    users.updateProfile (EXISTS users.ts:896)                -> preference mutations
//    vesselShipments.getVesselCrew (EXISTS vesselShipments.ts:742 ·
//      returns {crew, certifications, expiringCount}) -> STCW certs + watch
//
//  PERSONA GAP: VESSEL_OPERATOR persona NOT canonized (SKILL: "NEEDS FOUNDER
//  CANONIZATION"). displayName falls back to the literal "___" + PROPOSED chip.
//  No banned/retired name introduced.
//

import SwiftUI

struct VesselOperatorAccountScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselOperatorAccountBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct VesselAccountProfile: Decodable {
    let id: Int
    let name: String?          // PROPOSED persona — empty until canonized
    let role: String?
    let companyName: String?
    let crewId: String?
}

private struct VesselCertificate: Decodable, Identifiable {
    let id: Int
    let title: String
    let statusLabel: String?
    let expiring: Bool?
}

private struct WatchRest: Decodable {
    let restHours: Double?
    let windowHours: Double?
    let minHours: Double?
    let nextWatch: String?
}

private struct VesselSettingsPayload: Decodable {
    struct OperationalPreferences: Decodable {
        let distanceUnit: String
        let esangVoiceEnabled: Bool
    }
    let operationalPreferences: OperationalPreferences
}

private struct VesselNotificationPreferences: Decodable {
    let pushNotifications: Bool
}

private struct VesselSettingsMutationAck: Decodable {
    let success: Bool?
}

// MARK: - Body

private struct VesselOperatorAccountBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @State private var me: VesselAccountProfile? = nil
    @State private var certificates: [VesselCertificate] = []
    @State private var watch: WatchRest? = nil
    @State private var watchError: String? = nil
    @State private var notificationsOn = false
    @State private var voiceOn = true
    @State private var distanceUnit = "nautical_miles"
    @State private var preferencesLoaded = false
    @State private var preferencesError: String? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var saveError: String? = nil
    @State private var showSignOutConfirm = false

    /// Which hub cards are expanded. Consolidation: the Me tab rendered 17
    /// always-open ops groups (~74 rows) in one scroll. Rebuilt into 5 bespoke
    /// collapsible hubs by canonical taxonomy — every destination preserved.
    /// Every hub starts collapsed until the user opens it.
    @SceneStorage("vessel.operator.me.expandedHub") private var expandedHubId: String = ""
    @SceneStorage("vessel.operator.me.returnAnchor") private var returnAnchor: String = ""

    private var displayName: String {
        let n = me?.name?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "Vessel Operator" : n
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    if loading {
                        LifecycleCard { Text("Loading account…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                    } else {
                        identityCard
                        EusoCardIssuePanel(
                            title: "EusoCard",
                            subtitle: "Vessel spend card backed by EusoWallet Treasury"
                        )
                        bookingsHub
                        trackingTerminalHub
                        customsComplianceHub
                        claimsRecoveryHub
                        financeFleetHub
                        crewPreferencesHub
                        signOut
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 14).padding(.top, 8)
            }
            .task {
                await load()
                restorePosition(using: proxy)
            }
            .eusoRefreshable { await load() }
        }
        .alert("Settings", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await session.signOut() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · MY ACCOUNT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Account").font(.system(size: 26, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Your account · profile, certificates, watch & preferences")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var identityCard: some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 14) {
                EditableProfileAvatar(size: 68)
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName).font(.system(size: 20, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Text(["VESSEL OPERATOR", me?.companyName]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                    if let crewId = me?.crewId?.trimmingCharacters(in: .whitespacesAndNewlines), !crewId.isEmpty {
                        Text("Crew ID \(crewId)")
                            .font(.system(size: 11)).monospaced().foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Operations hub (journey entry points)
    //
    // Wires the vessel-operator's working surfaces into the real journey.
    // Each row posts `.eusoVesselNavSwap{screenId}`, which the
    // VesselOperatorSurface resolves out of ScreenRegistry (RBAC-gated by
    // RoleAccess.canRender) and pushes onto the role stack. Without this,
    // these screens were registered but unreachable — islands in dev
    // chrome. Grouped by the operator's task domains so the bid board,
    // D&D money tools, booking edits, and drayage dispatch are reachable
    // from the Me tab (mirrors the Driver Me-hub IA).
    // Hub 1 — Bookings & Tenders (bids, bookings, shipments, intermodal)
    private var bookingsHub: some View {
        hubCard(id: "bookings", icon: "shippingbox.fill",
                title: "Bookings & Tenders",
                summary: "Bids · Bookings · Shipments · Intermodal", rowCount: 12) {
            opsGroup("CREATE & REGISTER", [
                ("VeslOperationsLedger", "plus.rectangle.on.folder", "Operations ledger", "Rates · voyages · manifests · bunker · containers"),
            ])
            opsGroup("BIDS & TENDERS", [
                ("Vesl709", "sailboat.fill", "Bid board", "Award open lanes by rate"),
            ])
            opsGroup("BOOKINGS", [
                ("Vesl669", "doc.badge.gearshape", "Booking amendment", "Propose changes to a booking"),
                ("Vesl706", "arrow.triangle.2.circlepath", "Rebooking suggestions", "Reroute on a blanked sailing"),
            ])
            opsGroup("BOOKINGS & SHIPMENTS", [
                ("Vesl008", "arrow.triangle.swap", "Intermodal journey", "End-to-end leg map"),
                ("Vesl009", "doc.text", "Tender workflow", "Respond to ocean tenders"),
                ("Vesl653", "shippingbox", "Booking detail", "Carrier booking record"),
                ("Vesl657", "arrow.up.circle", "Status update", "Post a booking milestone"),
                ("Vesl677", "doc.badge.gearshape", "Carrier tender workflow", "Carrier-side tender steps"),
                ("Vesl680", "rectangle.split.3x1", "Intermodal segment board", "Per-leg segment status"),
                ("Vesl688", "calendar", "Sailing schedule", "Vessel sailing calendar"),
            ])
            opsGroup("INTERMODAL", [
                ("Vesl737", "truck.box.fill", "Drayage orders", "Dispatch the inland leg"),
            ])
        }
    }

    // Hub 2 — Tracking & Terminal (tracking, timeline, berth/terminal, D&D, reefer)
    private var trackingTerminalHub: some View {
        hubCard(id: "tracking", icon: "point.3.connected.trianglepath.dotted",
                title: "Tracking & Terminal",
                summary: "Tracking · Timeline · Berth · D&D · Reefer", rowCount: 34) {
            opsGroup("TRACKING & ANALYTICS", [
                ("Vesl770", "point.topleft.down.curvedto.point.bottomright.up", "ETA prediction", "Arrival confidence cone"),
                ("Vesl782", "chart.bar.doc.horizontal", "Dwell analysis", "Free-time exposure by terminal"),
                ("Vesl816", "trophy", "Top shippers", "Ranked by volume & completion"),
            ])
            opsGroup("TRACKING & TIMELINE", [
                ("Vesl655", "location.viewfinder", "Container positions", "Where your boxes are"),
                ("Vesl666", "clock.arrow.circlepath", "Container timeline", "Event history per box"),
                ("Vesl667", "link.circle", "Chain of custody", "Custody handoff log"),
                ("Vesl671", "cloud.sun", "Marine weather routing", "On-route severity + reroute"),
            ])
            opsGroup("BERTH, TERMINAL & D&D", [
                ("Vesl664", "calendar.badge.clock", "Terminal appointment", "Schedule a terminal slot"),
                ("Vesl698", "rectangle.portrait.and.arrow.right", "Berth window", "Assigned berth windows"),
                ("Vesl697", "ferry.fill", "Port operations", "Live terminal ops console"),
                ("Vesl658", "hourglass", "Demurrage & detention", "Free-time exposure summary"),
            ])
            opsGroup("DEMURRAGE & DETENTION", [
                ("Vesl757", "envelope.badge", "Detention letters", "Notice ledger by facility"),
                ("Vesl815", "checkmark.seal", "Charge approval", "Approve / dispute D&D charges"),
                ("Vesl792", "function", "Demurrage calculator", "Tier the billable detention"),
                ("Vesl772", "chart.bar.xaxis", "Demurrage analytics", "Avoidable vs baseline trend"),
                ("Vesl735", "bell.badge", "Demurrage alerts", "Free-time cutoffs at risk"),
                ("Vesl784", "timer", "Detention tracking", "Live detention accrual"),
                ("Vesl731", "list.bullet.rectangle", "Accessorial charges", "Code-keyed charge ledger"),
            ])
            opsGroup("REEFER & RESILIENCE", [
                ("Vesl820", "thermometer.snowflake", "Reefer pre-cool", "FSMA pre-cool gate"),
                ("Vesl821", "exclamationmark.triangle", "Reefer alert console", "Cold-chain deviations"),
                ("Vesl689", "bolt.horizontal.circle", "Network disruption", "Blank sailings & reroutes"),
                ("Vesl730", "calendar.badge.exclamationmark", "Blank sailing watch", "Cancelled sailings triage"),
            ])
            // 2026-08-11 vessel :04 fire §16 — the port & terminal ground-operations band.
            // These nine were catalog-only until this fire (wireframe + Swift port existed,
            // no Views/Vessel integration and therefore no way in). 699 Vessel Particulars
            // is a fleet/statutory surface and lives under Customs & Compliance instead.
            opsGroup("PORT CALL & QUAY", [
                ("Vesl703", "ferry", "Port lineup", "Quay metres vs waiting hulls"),
                ("Vesl690", "building.2", "Terminal status", "Congestion weighted by your boxes"),
                ("Vesl692", "arrow.triangle.branch", "Transshipment connection", "Feeder → onward buffer"),
                ("Vesl704", "square.grid.3x3", "Bay plan", "Stow placement + stack weight"),
                ("Vesl691", "person.3", "Crew call board", "Muster state per hand"),
            ])
            opsGroup("TERMINAL GROUND OPS", [
                ("Vesl707", "list.bullet.rectangle.portrait", "Container movement log", "Every move on a 24h raster"),
                ("Vesl744", "arrow.left.arrow.right.square", "Terminal gate log", "Turn time against appointment"),
                ("Vesl780", "arrow.up.arrow.down.square", "Terminal move queue", "Queue depth + when it drains"),
                ("Vesl781", "dollarsign.square", "Drop yard operations", "Per-diem burn past free time"),
            ])
            // 2026-08-25 vessel fire — the alongside band. 835/839/836 were
            // DESIGN_CLEARED on 08-17 with all four artifacts on disk, yet every
            // one was referenced ONLY by the ContentView registry that declares
            // it: registered, compiled, shipped in the binary, and reachable by
            // nobody. Same class as the routeless BrokerDashboard. Grouped by the
            // port call's actual sequence — pilot aboard, cargo worked, time
            // recorded — not by catalog number.
            opsGroup("ALONGSIDE & PORT TIME", [
                ("Vesl839", "water.waves", "Pilotage & marine services", "Order pilot, tugs and linesmen for a call"),
                ("Vesl835", "square.stack.3d.up.fill", "Load & discharge sequence", "Plan the crane split and move order"),
                ("Vesl836", "stopwatch", "Laytime & statement of facts", "Port time on the clock that bills"),
            ])
        }
    }

    // Hub 3 — Customs & Compliance (customs filings, port state, IMDG, crew, emissions)
    private var customsComplianceHub: some View {
        hubCard(id: "customs", icon: "checkmark.shield.fill",
                title: "Customs & Compliance",
                summary: "Customs · Port state · IMDG · Crew · Emissions", rowCount: 17) {
            opsGroup("CUSTOMS", [
                ("Vesl814", "doc.badge.plus", "Customs entry filing", "File the CBP 7501 entry"),
                ("Vesl789", "clock.arrow.circlepath", "Customs status update", "Advance customs disposition"),
                // 2026-08-25 — AMS is the 24h-before-lading filing; it belongs
                // beside the entry filing it precedes, not in a band of its own.
                ("Vesl838", "doc.plaintext", "AMS 24-hour manifest", "Lodge cargo 24h before lading"),
            ])
            opsGroup("CUSTOMS & COMPLIANCE", [
                ("Vesl662", "exclamationmark.octagon", "Exceptions & holds", "Active blocks on your boxes"),
                ("Vesl663", "doc.badge.plus", "CBP entry detail", "7501 entry line detail"),
                ("Vesl668", "exclamationmark.triangle", "IMDG hazmat manifest", "DG placards + segregation"),
                ("Vesl678", "checkmark.shield", "Port state control", "PSC inspection status"),
                ("Vesl701", "list.bullet.clipboard", "IMDG DG rules", "DG segregation rules"),
                ("Vesl705", "bell.badge", "CBP alerts", "Customs hold notifications"),
                ("Vesl710", "exclamationmark.triangle.fill", "Marine casualty", "Incident & casualty filing"),
                ("Vesl738", "scalemass", "VGM declaration", "SOLAS verified gross mass"),
            ])
            opsGroup("CREW & EMISSIONS", [
                ("Vesl654", "checkmark.seal", "Crew certifications", "STCW cert status"),
                ("Vesl711", "bed.double", "Crew rest hours", "MLC rest-hour compliance"),
                ("Vesl681", "leaf", "Emissions CII", "Carbon intensity indicator"),
            ])
            // 2026-08-11 vessel :04 fire §16 — statutory ship's registry card.
            opsGroup("SHIP & CERTIFICATES", [
                ("Vesl699", "ruler", "Vessel particulars", "Dimensions vs port limits + cert horizon"),
                // 2026-08-25 — two statutory instruments the master signs and a
                // port state inspects. Both were catalog-only until this fire.
                ("Vesl840", "lock.shield", "ISPS security & DoS", "Security level and declaration of security"),
                ("Vesl843", "drop.triangle", "Ballast water management", "Exchange or treatment against the plan"),
            ])
        }
    }

    // Hub 4 — Claims & Recovery (claims lifecycle, disputes, overcharge recovery)
    private var claimsRecoveryHub: some View {
        hubCard(id: "claims", icon: "doc.text.magnifyingglass",
                title: "Claims & Recovery",
                summary: "Claims · Disputes · Overcharge recovery", rowCount: 12) {
            opsGroup("CLAIMS", [
                ("Vesl800", "doc.text.magnifyingglass", "Claims dashboard", "Open / pending / resolved + aging"),
                ("Vesl801", "list.bullet.clipboard", "Claims list", "Filter & search all claims"),
                ("Vesl808", "arrow.right.doc.on.clipboard", "Claim workflow", "Advance a claim file → close"),
                ("Vesl732", "shippingbox.and.arrow.backward", "Cargo claim", "File loss & damage on a load"),
                ("Vesl811", "chart.pie", "Claims analytics", "Loss trend & recovery rate"),
                ("Vesl812", "doc.on.doc", "Claim templates", "Pre-built claim forms"),
                // 2026-08-25 — the note of protest is filed BEFORE a claim exists,
                // to preserve the right to bring one. It sits with claims because
                // that is what it protects, and it was unreachable until this fire.
                ("Vesl841", "exclamationmark.bubble", "Note of protest", "Reserve the claim before discharge"),
            ])
            opsGroup("DISPUTE & RECOVERY", [
                ("Vesl802", "creditcard", "Claim payments", "Reconcile claim payouts"),
                ("Vesl804", "arrow.uturn.backward.circle", "Overcharge recovery", "Audit & recover overcharges"),
                ("Vesl805", "shield.lefthalf.filled", "Loss prevention", "Cargo loss risk + mitigation"),
                ("Vesl809", "scalemass", "Dispute resolution", "Resolve carrier disputes"),
                ("Vesl810", "person.2.badge.gearshape", "Dispute mediation", "Mediator sessions & briefs"),
            ])
        }
    }

    // Hub 5 — Finance & Fleet (position/finance, commercial billing, equipment)
    private var financeFleetHub: some View {
        hubCard(id: "finance", icon: "dollarsign.circle",
                title: "Finance & Fleet",
                summary: "Position · Settlement · Billing · Equipment", rowCount: 19) {
            opsGroup("POSITION & FINANCE", [
                ("Vesl660", "dot.radiowaves.up.forward", "Live position", "AIS track + ETA to berth"),
                ("Vesl661", "point.3.connected.trianglepath.dotted", "Port calls", "Rotation & berth schedule"),
                ("Vesl674", "list.bullet.rectangle.portrait", "Cost breakdown", "Per-move charge detail"),
                ("Vesl696", "banknote", "Settlement batch", "Approve carrier payouts"),
                ("Vesl670", "fuelpump", "Bunker prices", "VLSFO/MGO regional trend"),
                // 2026-08-25 — the delivered-quantity record, next to the price
                // curve it settles against. Catalog-only until this fire.
                ("Vesl842", "fuelpump.fill", "Bunkering & BDN", "Delivered quantity and grade on the note"),
                ("Vesl708", "leaf", "Shipment CO₂", "CII rating + GHG statement"),
            ])
            opsGroup("COMMERCIAL & BILLING", [
                ("Vesl659", "fuelpump.circle", "Bunker FSC", "Bunker surcharge"),
                ("Vesl682", "star.circle", "Carrier scorecard", "Rank carriers by score"),
                ("Vesl684", "doc.text", "Settlement", "Settlement summary"),
                ("Vesl685", "calendar.badge.clock", "Bunker FSC schedule", "FSC schedule by period"),
                ("Vesl687", "tablecells", "Ocean rate lookup", "Spot & contract rates"),
                ("Vesl700", "doc.text.magnifyingglass", "Freight bill audit", "Audit ocean freight bills"),
                ("Vesl712", "dollarsign.circle", "Financial summary", "Financial overview"),
            ])
            opsGroup("EQUIPMENT & FLEET", [
                ("Vesl673", "doc.text.below.ecg", "Container lease", "Box / chassis leases"),
                // 2026-08-25 — the EOR is the estimate that turns box damage into
                // a cost, so it belongs with the equipment it prices.
                ("Vesl837", "wrench.and.screwdriver", "Container M&R EOR", "Estimate of repair before the box moves"),
                ("Vesl676", "heart.text.square", "Equipment health", "Reefer & box condition"),
                ("Vesl683", "waveform.path.ecg", "Fleet health", "Fleet-wide condition"),
                ("Vesl702", "thermometer.snowflake", "Reefer monitoring", "Live reefer telemetry"),
            ])
        }
    }

    // MARK: - Hub primitive (bespoke collapsible card, parity with 350 / 713)

    /// A collapsible hub card: gradient-icon header with title, one-line summary
    /// and a row-count pill that toggles the body open/closed on tap. Collapsed
    /// by default (except the first hub) so the Me tab reads as a clean stack of
    /// hubs rather than a ~74-row flat list.
    @ViewBuilder
    private func hubCard<Content: View>(id: String,
                                        icon: String,
                                        title: String,
                                        summary: String,
                                        rowCount: Int,
                                        @ViewBuilder content: () -> Content) -> some View {
        let isOpen = expandedHubId == id
        LifecycleCard {
            Button {
                withAnimation(.easeOut(duration: 0.22)) {
                    expandedHubId = isOpen ? "" : id
                    returnAnchor = "hub-\(id)"
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text(summary)
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                    Text("\(rowCount)")
                        .font(.system(size: 10, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(palette.bgCardSoft))
                        .overlay(Capsule().strokeBorder(palette.borderFaint.opacity(0.5)))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                Rectangle()
                    .fill(palette.borderFaint.opacity(0.4))
                    .frame(height: 1)
                    .padding(.vertical, 6)
                VStack(spacing: 6) { content() }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .id("hub-\(id)")
    }

    @ViewBuilder
    private func opsGroup(_ title: String, _ rows: [(id: String, icon: String, title: String, sub: String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 8, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary.opacity(0.8))
            LifecycleCard {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, r in
                        Button {
                            returnAnchor = "row-\(r.id)"
                            openOps(r.id)
                        } label: { opsRow(icon: r.icon, title: r.title, subtitle: r.sub) }
                            .buttonStyle(.plain)
                            .id("row-\(r.id)")
                        if idx < rows.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 44)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func opsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.16)).frame(width: 32, height: 32)
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.vertical, 8).contentShape(Rectangle())
    }

    private func openOps(_ screenId: String) {
        NotificationCenter.default.post(name: .eusoVesselNavSwap, object: nil, userInfo: ["screenId": screenId])
    }

    private var crewPreferencesHub: some View {
        hubCard(
            id: "account",
            icon: "person.crop.circle",
            title: "Crew & Preferences",
            summary: "Certificates · Watch telemetry · Notifications · Units · Voice",
            rowCount: 3
        ) {
            certificatesContent
            sectionDivider
            watchContent
            sectionDivider
            preferencesContent
        }
    }

    private var certificatesContent: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CERTIFICATES · ON FILE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if certificates.isEmpty {
                Text("No certificate records were returned.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                ForEach(certificates) { certificate in
                    HStack {
                        Text(certificate.title).font(EType.body).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(certificate.statusLabel ?? "Status unavailable")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(
                                certificate.expiring == true
                                    ? Brand.warning
                                    : (certificate.statusLabel == nil ? palette.textTertiary : Brand.success)
                            )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var watchContent: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("WATCH · REST HOURS · MLC 2006 / STCW")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if let watch,
               let rest = watch.restHours,
               let window = watch.windowHours,
               let minimum = watch.minHours {
                HStack {
                    Text("Rest \(rest, specifier: "%.1f")h / \(window, specifier: "%.1f")h · minimum \(minimum, specifier: "%.1f")h")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(rest >= minimum ? "minimum met" : "below minimum")
                        .font(EType.bodyStrong)
                        .foregroundStyle(rest >= minimum ? Brand.success : Brand.danger)
                }
                ProgressView(value: rest, total: max(window, 1)).tint(LinearGradient.primary)
                if let nextWatch = watch.nextWatch?.trimmingCharacters(in: .whitespacesAndNewlines), !nextWatch.isEmpty {
                    Text("Next recorded watch · \(nextWatch)")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                Text(watchError ?? "No current watch or rest-hour telemetry was returned.")
                    .font(EType.caption).foregroundStyle(watchError == nil ? palette.textSecondary : Brand.warning)
            }
        }
    }

    private var preferencesContent: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("PREFERENCES · SAVED TO YOUR ACCOUNT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if let preferencesError {
                Text(preferencesError).font(EType.caption).foregroundStyle(Brand.warning)
            }
            Toggle(isOn: Binding(
                get: { notificationsOn },
                set: { value in
                    guard preferencesLoaded else { return }
                    let previous = notificationsOn
                    notificationsOn = value
                    Task { await saveNotifications(value, previous: previous) }
                }
            )) {
                Text("Push notifications").font(EType.body).foregroundStyle(palette.textPrimary)
            }
            .tint(Brand.info)
            .disabled(!preferencesLoaded)

            Picker("Distance units", selection: Binding(
                get: { distanceUnit },
                set: { value in
                    guard preferencesLoaded else { return }
                    let previous = distanceUnit
                    distanceUnit = value
                    Task { await saveOperationalPreference(distanceUnit: value, previousDistanceUnit: previous) }
                }
            )) {
                Text("Miles").tag("miles")
                Text("Kilometers").tag("kilometers")
                Text("Nautical miles").tag("nautical_miles")
            }
            .pickerStyle(.menu)
            .disabled(!preferencesLoaded)

            Toggle(isOn: Binding(
                get: { voiceOn },
                set: { value in
                    guard preferencesLoaded else { return }
                    let previous = voiceOn
                    voiceOn = value
                    Task { await saveOperationalPreference(esangVoiceEnabled: value, previousVoice: previous) }
                }
            )) {
                Text("ESANG AI voice").font(EType.body).foregroundStyle(palette.textPrimary)
            }
            .tint(Brand.info)
            .disabled(!preferencesLoaded)
        }
    }

    private var sectionDivider: some View {
        Rectangle().fill(palette.borderFaint.opacity(0.5)).frame(height: 1).padding(.vertical, 4)
    }

    private var signOut: some View {
        CTAButton(
            title: "Sign out",
            action: { showSignOutConfirm = true },
            leadingIcon: "rectangle.portrait.and.arrow.right"
        )
    }

    // MARK: - Load + mutate

    private func load() async {
        loading = true
        loadError = nil
        watchError = nil
        struct Empty: Encodable {}
        struct ProfileOut: Decodable { let certifications: [VesselCertificate]?; let watch: WatchRest? }
        do {
            self.me = try await EusoTripAPI.shared.query("users.me", input: Empty())
        } catch {
            loadError = error.eusoUserCopy
        }
        if loadError == nil {
            do {
                let crew: ProfileOut = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselCrew", input: Empty()
                )
                self.certificates = crew.certifications ?? []
                self.watch = crew.watch
            } catch {
                self.certificates = []
                self.watch = nil
                self.watchError = error.eusoUserCopy
            }
        }
        await loadPreferences()
        loading = false
    }

    private func loadPreferences() async {
        struct Empty: Encodable {}
        preferencesLoaded = false
        preferencesError = nil
        do {
            async let settingsRequest: VesselSettingsPayload = EusoTripAPI.shared.query(
                "settings.getSettings", input: Empty()
            )
            async let notificationsRequest: VesselNotificationPreferences = EusoTripAPI.shared.query(
                "users.getNotificationPreferences", input: Empty()
            )
            let (settings, notifications) = try await (settingsRequest, notificationsRequest)
            distanceUnit = settings.operationalPreferences.distanceUnit
            voiceOn = settings.operationalPreferences.esangVoiceEnabled
            notificationsOn = notifications.pushNotifications
            preferencesLoaded = true
        } catch {
            preferencesError = error.eusoUserCopy
        }
    }

    private func saveNotifications(_ value: Bool, previous: Bool) async {
        struct PrefIn: Encodable { let pushNotifications: Bool }
        do {
            let out: VesselSettingsMutationAck = try await EusoTripAPI.shared.mutation(
                "users.updateNotificationPreferences",
                input: PrefIn(pushNotifications: value))
            if out.success != true {
                notificationsOn = previous
                saveError = "Couldn't save notification preference."
            }
        } catch {
            notificationsOn = previous
            saveError = error.eusoUserCopy
        }
    }

    private func saveOperationalPreference(
        distanceUnit newDistanceUnit: String? = nil,
        esangVoiceEnabled: Bool? = nil,
        previousDistanceUnit: String? = nil,
        previousVoice: Bool? = nil
    ) async {
        struct Input: Encodable {
            let distanceUnit: String?
            let esangVoiceEnabled: Bool?
        }
        do {
            let out: VesselSettingsMutationAck = try await EusoTripAPI.shared.mutation(
                "settings.updateOperationalPreferences",
                input: Input(distanceUnit: newDistanceUnit, esangVoiceEnabled: esangVoiceEnabled)
            )
            guard out.success == true else {
                throw EusoTripAPIError.trpcError("The preference was not saved.")
            }
        } catch {
            if let previousDistanceUnit { distanceUnit = previousDistanceUnit }
            if let previousVoice { voiceOn = previousVoice }
            saveError = error.eusoUserCopy
        }
    }

    private func restorePosition(using proxy: ScrollViewProxy) {
        eusoRestoreScrollPosition(
            using: proxy,
            anchor: returnAnchor,
            fallback: "hub-\(expandedHubId.isEmpty ? "bookings" : expandedHubId)"
        )
    }
}

#Preview("656 · Vessel Operator Account · Night") { VesselOperatorAccountScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("656 · Vessel Operator Account · Light") { VesselOperatorAccountScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
