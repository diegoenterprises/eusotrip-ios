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

// MARK: - Body

private struct VesselOperatorAccountBody: View {
    @Environment(\.palette) private var palette
    @State private var me: VesselAccountProfile? = nil
    @State private var certificates: [VesselCertificate] = []
    @State private var watch: WatchRest? = nil
    @State private var notificationsOn = true
    @State private var voiceOn = true
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var saveError: String? = nil

    private var displayName: String {
        let n = me?.name?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "___" : n
    }
    private var personaPending: Bool {
        (me?.name?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading account…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    identityCard
                    operationsCard
                    certificatesCard
                    watchCard
                    preferencesCard
                    signOut
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("Settings", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · MY ACCOUNT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Account").font(.system(size: 26, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("users.me · profile, certificates, watch & preferences")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var identityCard: some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(palette.bgCardSoft).frame(width: 68, height: 68)
                    Image(systemName: "person.fill").font(.system(size: 26)).foregroundStyle(palette.textTertiary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(displayName).font(.system(size: 20, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        if personaPending {
                            Text("PROPOSED").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(Brand.warning)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Brand.warning.opacity(0.16)))
                        }
                    }
                    Text("VESSEL OPERATOR · \(me?.companyName ?? "___ OPERATOR (PROPOSED)")")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                    Text("crew id \(me?.crewId ?? "—") · STCW II/1 active")
                        .font(.system(size: 11)).monospaced().foregroundStyle(palette.textTertiary)
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
    private var operationsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("OPERATIONS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            opsGroup("BIDS & TENDERS", [
                ("Vesl709", "sailboat.fill", "Bid board", "Award open lanes by rate"),
            ])
            opsGroup("BOOKINGS", [
                ("Vesl669", "doc.badge.gearshape", "Booking amendment", "Propose changes to a booking"),
                ("Vesl706", "arrow.triangle.2.circlepath", "Rebooking suggestions", "Reroute on a blanked sailing"),
            ])
            opsGroup("DEMURRAGE & DETENTION", [
                ("Vesl757", "envelope.badge", "Detention letters", "Notice ledger by facility"),
                ("Vesl815", "checkmark.seal", "Charge approval", "Approve / dispute D&D charges"),
                ("Vesl792", "function", "Demurrage calculator", "Tier the billable detention"),
                ("Vesl772", "chart.bar.xaxis", "Demurrage analytics", "Avoidable vs baseline trend"),
                ("Vesl735", "bell.badge", "Demurrage alerts", "Free-time cutoffs at risk"),
                ("Vesl784", "timer", "Detention tracking", "Live detention accrual"),
            ])
            opsGroup("INTERMODAL", [
                ("Vesl737", "truck.box.fill", "Drayage orders", "Dispatch the inland leg"),
            ])
            opsGroup("CLAIMS", [
                ("Vesl800", "doc.text.magnifyingglass", "Claims dashboard", "Open / pending / resolved + aging"),
                ("Vesl801", "list.bullet.clipboard", "Claims list", "Filter & search all claims"),
                ("Vesl808", "arrow.right.doc.on.clipboard", "Claim workflow", "Advance a claim file → close"),
                ("Vesl732", "shippingbox.and.arrow.backward", "Cargo claim", "File loss & damage on a load"),
                ("Vesl811", "chart.pie", "Claims analytics", "Loss trend & recovery rate"),
                ("Vesl812", "doc.on.doc", "Claim templates", "Pre-built claim forms"),
            ])
            opsGroup("CUSTOMS", [
                ("Vesl814", "doc.badge.plus", "Customs entry filing", "File the CBP 7501 entry"),
                ("Vesl789", "clock.arrow.circlepath", "Customs status update", "Advance customs disposition"),
            ])
            opsGroup("TRACKING & ANALYTICS", [
                ("Vesl770", "point.topleft.down.curvedto.point.bottomright.up", "ETA prediction", "Arrival confidence cone"),
                ("Vesl782", "chart.bar.doc.horizontal", "Dwell analysis", "Free-time exposure by terminal"),
                ("Vesl816", "trophy", "Top shippers", "Ranked by volume & completion"),
            ])
            opsGroup("REEFER & RESILIENCE", [
                ("Vesl820", "thermometer.snowflake", "Reefer pre-cool", "FSMA pre-cool gate"),
                ("Vesl821", "exclamationmark.triangle", "Reefer alert console", "Cold-chain deviations"),
                ("Vesl689", "bolt.horizontal.circle", "Network disruption", "Blank sailings & reroutes"),
            ])
            opsGroup("DISPUTE & RECOVERY", [
                ("Vesl802", "creditcard", "Claim payments", "Reconcile claim payouts"),
                ("Vesl804", "arrow.uturn.backward.circle", "Overcharge recovery", "Audit & recover overcharges"),
                ("Vesl805", "shield.lefthalf.filled", "Loss prevention", "Cargo loss risk + mitigation"),
                ("Vesl809", "scalemass", "Dispute resolution", "Resolve carrier disputes"),
                ("Vesl810", "person.2.badge.gearshape", "Dispute mediation", "Mediator sessions & briefs"),
            ])
            opsGroup("POSITION & FINANCE", [
                ("Vesl660", "dot.radiowaves.up.forward", "Live position", "AIS track + ETA to berth"),
                ("Vesl661", "point.3.connected.trianglepath.dotted", "Port calls", "Rotation & berth schedule"),
                ("Vesl674", "list.bullet.rectangle.portrait", "Cost breakdown", "Per-move charge detail"),
                ("Vesl696", "banknote", "Settlement batch", "Approve carrier payouts"),
                ("Vesl670", "fuelpump", "Bunker prices", "VLSFO/MGO regional trend"),
                ("Vesl708", "leaf", "Shipment CO₂", "CII rating + GHG statement"),
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
            opsGroup("TRACKING & TIMELINE", [
                ("Vesl655", "location.viewfinder", "Container positions", "Where your boxes are"),
                ("Vesl666", "clock.arrow.circlepath", "Container timeline", "Event history per box"),
                ("Vesl667", "link.circle", "Chain of custody", "Custody handoff log"),
                ("Vesl671", "cloud.sun", "Marine weather routing", "On-route severity + reroute"),
            ])
            opsGroup("BERTH, TERMINAL & D&D", [
                ("Vesl664", "calendar.badge.clock", "Terminal appointment", "Schedule a terminal slot"),
                ("Vesl698", "rectangle.portrait.and.arrow.right", "Berth window", "Assigned berth windows"),
                ("Vesl658", "hourglass", "Demurrage & detention", "Free-time exposure summary"),
            ])
            opsGroup("CUSTOMS & COMPLIANCE", [
                ("Vesl662", "exclamationmark.octagon", "Exceptions & holds", "Active blocks on your boxes"),
                ("Vesl663", "doc.badge.plus", "CBP entry detail", "7501 entry line detail"),
                ("Vesl668", "exclamationmark.triangle", "IMDG hazmat manifest", "DG placards + segregation"),
                ("Vesl678", "checkmark.shield", "Port state control", "PSC inspection status"),
                ("Vesl701", "list.bullet.clipboard", "IMDG DG rules", "DG segregation rules"),
                ("Vesl705", "bell.badge", "CBP alerts", "Customs hold notifications"),
                ("Vesl710", "exclamationmark.triangle.fill", "Marine casualty", "Incident & casualty filing"),
            ])
            opsGroup("EQUIPMENT & FLEET", [
                ("Vesl673", "doc.text.below.ecg", "Container lease", "Box / chassis leases"),
                ("Vesl676", "heart.text.square", "Equipment health", "Reefer & box condition"),
                ("Vesl683", "waveform.path.ecg", "Fleet health", "Fleet-wide condition"),
                ("Vesl702", "thermometer.snowflake", "Reefer monitoring", "Live reefer telemetry"),
            ])
            opsGroup("CREW & EMISSIONS", [
                ("Vesl654", "checkmark.seal", "Crew certifications", "STCW cert status"),
                ("Vesl711", "bed.double", "Crew rest hours", "MLC rest-hour compliance"),
                ("Vesl681", "leaf", "Emissions CII", "Carbon intensity indicator"),
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
        }
    }

    @ViewBuilder
    private func opsGroup(_ title: String, _ rows: [(id: String, icon: String, title: String, sub: String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 8, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary.opacity(0.8))
            LifecycleCard {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, r in
                        Button { openOps(r.id) } label: { opsRow(icon: r.icon, title: r.title, subtitle: r.sub) }
                            .buttonStyle(.plain)
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

    private var certificatesCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CERTIFICATES · getVesselCrew").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(spacing: Space.s2) {
                    ForEach(certificates) { c in
                        HStack {
                            Text(c.title).font(EType.body).foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(c.statusLabel ?? "—").font(.system(size: 11, weight: .bold))
                                .foregroundStyle((c.expiring ?? false) ? Brand.warning : Brand.success)
                        }
                    }
                }
            }
        }
    }

    private var watchCard: some View {
        let rest = watch?.restHours ?? 11.0
        let window = watch?.windowHours ?? 24.0
        let minH = watch?.minHours ?? 10.0
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("WATCH · REST HOURS · MLC 2006 / STCW").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Rest \(rest, specifier: "%.1f")h / \(Int(window))h · min \(Int(minH))h")
                            .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(rest >= minH ? "compliant" : "short rest")
                            .font(EType.bodyStrong).foregroundStyle(rest >= minH ? Brand.success : Brand.danger)
                    }
                    ProgressView(value: rest, total: max(window, 1)).tint(LinearGradient.primary)
                    Text("Next watch \(watch?.nextWatch ?? "20:00–24:00") · 4-on / 8-off rotation")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("PREFERENCES · users.updateProfile").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(spacing: Space.s3) {
                    Toggle(isOn: $notificationsOn) {
                        Text("Push notifications").font(EType.body).foregroundStyle(palette.textPrimary)
                    }
                    .tint(Brand.info)
                    .onChange(of: notificationsOn) { _, v in Task { await savePref("notifications", v) } }
                    HStack { Text("Distance units").font(EType.body).foregroundStyle(palette.textPrimary); Spacer(); Text("nautical mi ›").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textSecondary) }
                    HStack { Text("ESANG AI voice").font(EType.body).foregroundStyle(palette.textPrimary); Spacer(); Text(voiceOn ? "on ›" : "off ›").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.info) }
                }
            }
        }
    }

    private var signOut: some View {
        CTAButton(title: "Sign out", leadingIcon: "rectangle.portrait.and.arrow.right")
    }

    // MARK: - Load + mutate

    private func load() async {
        loading = true; loadError = nil
        struct Empty: Encodable {}
        struct ProfileOut: Decodable { let certifications: [VesselCertificate]?; let watch: WatchRest? }
        do {
            self.me = try await EusoTripAPI.shared.query("users.me", input: Empty())
            let crew: ProfileOut = try await EusoTripAPI.shared.query("vesselShipments.getVesselCrew", input: Empty())
            self.certificates = crew.certifications ?? []
            self.watch = crew.watch
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func savePref(_ key: String, _ value: Bool) async {
        // See §6 FIX 3 — re-pointed from users.updateProfile (which silently
        // dropped {key,value}) to the real users.updateNotificationPreferences.
        struct PrefIn: Encodable { let pushNotifications: Bool }
        struct Out: Decodable { let success: Bool? }
        guard key == "notifications" else { return }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "users.updateNotificationPreferences",
                input: PrefIn(pushNotifications: value))
            if out.success != true {
                notificationsOn = !value
                saveError = "Couldn't save notification preference."
            }
        } catch {
            notificationsOn = !value
            saveError = (error as? EusoTripAPIError)?.errorDescription
                ?? "Couldn't save notification preference."
        }
    }
}

#Preview("656 · Vessel Operator Account · Night") { VesselOperatorAccountScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("656 · Vessel Operator Account · Light") { VesselOperatorAccountScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
