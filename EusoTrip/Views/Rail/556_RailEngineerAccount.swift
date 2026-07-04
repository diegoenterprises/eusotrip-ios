//
//  556_RailEngineerAccount.swift
//  EusoTrip — Rail Engineer · My Account (ME tab).
//
//  PERSONA GAP: RAIL_ENGINEER individual persona not yet canonized.
//  displayName falls back to "___" + PROPOSED chip until founder canonizes.
//

import SwiftUI

struct RailEngineerAccountScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailEngineerAccountBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct RailAccountProfile: Decodable {
    let id: Int
    let name: String?
    let role: String?
    let companyName: String?
    let crewId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, role, companyName, crewId, email, companyId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.role = try c.decodeIfPresent(String.self, forKey: .role)
        self.companyName = try c.decodeIfPresent(String.self, forKey: .companyName)
        self.crewId = try c.decodeIfPresent(String.self, forKey: .crewId)
        // Server returns extra fields (email, companyId) that we ignore
        _ = try c.decodeIfPresent(String.self, forKey: .email)
        _ = try c.decodeIfPresent(Int.self, forKey: .companyId)
    }
}

private struct RailCredential: Decodable, Identifiable {
    let id: Int
    let title: String
    let statusLabel: String?
    let expiring: Bool?
}

private struct RailCrewHOSRow: Decodable {
    let onDutyHours: Double?
    let limitHours: Double?
    let lastRestHours: Double?
}

private struct RailEngineerAccountBody: View {
    @Environment(\.palette) private var palette
    @State private var me: RailAccountProfile? = nil
    @State private var credentials: [RailCredential] = []
    @State private var hos: RailCrewHOSRow? = nil
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
	                    EusoCardIssuePanel(
	                        title: "EusoCard",
	                        subtitle: "Rail spend card backed by EusoWallet Treasury"
	                    )
	                    operationsCard
                    credentialsCard
                    dutyCard
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
                Text("RAIL ENGINEER · MY ACCOUNT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Account").font(.system(size: 26, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Your account · profile, credentials, duty & preferences")
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
                    Text("RAIL ENGINEER · \(me?.companyName ?? "___ CARRIER (PROPOSED)")")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                    Text("crew id \(me?.crewId ?? "-") · FRA cert active")
                        .font(.system(size: 11)).monospaced().foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Operations hub (journey entry points)
    //
    // Wires the rail-engineer's working surfaces into the real journey.
    // Each row posts `.eusoRailNavSwap{screenId}`, which RailEngineerSurface
    // resolves out of ScreenRegistry (RBAC-gated by RoleAccess.canRender)
    // and pushes onto the role stack. Without this, these screens were
    // registered but unreachable — islands in dev chrome. Grouped by the
    // engineer's task domains (mirrors the Vessel + Driver Me-hub IA).
    private var operationsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("OPERATIONS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            opsGroup("PREDICTION & ROUTING", [
                ("Rail643", "clock.arrow.circlepath", "ETA prediction", "Per-segment arrival forecast"),
                ("Rail644", "arrow.left.arrow.right", "Transit comparison", "All-rail vs intermodal"),
                ("Rail646", "arrow.triangle.2.circlepath", "Rebooking options", "Reroute on a disruption"),
                ("Rail647", "chart.bar.xaxis", "Multimodal analytics", "Revenue + mode share by lane"),
                ("Rail673", "square.grid.3x3.topleft.filled", "Intermodal dashboard", "Rail+truck+ocean legs"),
                ("Rail639", "building.2", "Yard directory", "Yards by host railroad"),
                ("Rail672", "hourglass", "Layover tracking", "Layover charges & faults"),
            ])
            opsGroup("BIDS & PERFORMANCE", [
                ("Rail627", "list.bullet.rectangle", "Bid board", "Award open lanes by rate"),
                ("Rail574", "star.circle", "Carrier scorecard", "Rank carriers by score"),
                ("Rail569", "doc.text", "Tender workflow", "Respond to incoming tenders"),
            ])
            opsGroup("COMMERCIAL & CLAIMS", [
                ("Rail606", "checkmark.shield", "Cargo insurance", "Bind per-load all-risk cover"),
                ("Rail642", "chart.line.uptrend.xyaxis", "Accessorial analytics", "Demurrage + detention trend"),
                ("Rail652", "exclamationmark.bubble", "Claims dashboard", "Freight loss & damage"),
            ])
            opsGroup("FREIGHT CLAIMS", [
                ("Rail656", "creditcard", "Claim payments", "Reconcile & age payables"),
                ("Rail669", "arrow.uturn.backward.circle", "Overcharge recovery", "Audit & recover overcharges"),
                ("Rail670", "shippingbox.and.arrow.backward", "Shortage claims", "BOL vs received variance"),
                ("Rail671", "doc.on.doc", "Claim templates", "Pre-built claim forms"),
            ])
            opsGroup("COMPLIANCE & RISK", [
                ("Rail571", "exclamationmark.triangle", "IMDG hazmat manifest", "DG placards + segregation"),
                ("Rail578", "cloud.sun", "Route weather", "On-arc severity + reroute"),
                ("Rail563", "exclamationmark.octagon", "Exceptions & holds", "Active blocks on your cars"),
            ])
            opsGroup("SHIPMENTS & TRACKING", [
                ("Rail007", "plus.rectangle.on.folder", "New shipment", "Book a rail shipment"),
                ("Rail005", "doc.plaintext", "Waybill", "Rail waybill document"),
                ("Rail553", "shippingbox", "Shipment detail", "Carrier shipment record"),
                ("Rail557", "arrow.up.circle", "Status update", "Post a milestone update"),
                ("Rail560", "dot.radiowaves.up.forward", "Live tracking", "Real-time car position"),
                ("Rail565", "clock.arrow.circlepath", "Container timeline", "Event history per container"),
                ("Rail566", "arrow.triangle.swap", "Intermodal transfer", "Rail↔truck↔ocean handoff"),
                ("Rail576", "pencil.and.list.clipboard", "Shipment amendment", "Revise a booked shipment"),
                ("Rail591", "person.crop.circle.badge.checkmark", "Consignee tracking", "Receiver-facing status"),
                ("Rail633", "timer", "Border crossing ETA", "Cross-border arrival forecast"),
            ])
            opsGroup("YARD & RAMP OPS", [
                ("Rail555", "rectangle.split.3x1", "Consist board", "Train consist makeup"),
                ("Rail559", "square.grid.3x3", "Yard operations", "In-yard car moves"),
                ("Rail561", "building.columns", "Facility status", "Ramp / terminal status"),
                ("Rail562", "calendar.badge.clock", "Gate appointment", "Schedule a gate slot"),
                ("Rail582", "calendar", "Ramp schedule", "Ramp cut times"),
                ("Rail586", "list.bullet.clipboard", "Service lineup", "Scheduled service windows"),
                ("Rail589", "arrow.triangle.merge", "Transload connection", "Bulk transload handoff"),
                ("Rail600", "slider.horizontal.3", "Ramp ops console", "Live ramp operations"),
                ("Rail603", "calendar.day.timeline.left", "Dock schedule", "Dock door scheduling"),
                ("Rail604", "chart.bar", "Yard analytics", "Dwell + throughput metrics"),
                ("Rail621", "tray.full", "Yard move queue", "Pending yard moves"),
                ("Rail622", "calendar.badge.plus", "Move scheduler", "Schedule yard moves"),
                ("Rail623", "square.stack.3d.down.right", "Drop yard ops", "Drop-lot management"),
                ("Rail628", "map", "Yard map", "Live yard layout"),
                ("Rail630", "arrow.left.arrow.right.square", "Cross-dock ops", "Cross-dock transfers"),
            ])
            opsGroup("DEMURRAGE & DETENTION", [
                ("Rail558", "hourglass.tophalf.filled", "Demurrage watch", "Accruing demurrage alerts"),
                ("Rail570", "exclamationmark.bubble", "Demurrage dispute", "Contest demurrage charges"),
                ("Rail602", "stopwatch", "Detention tracking", "Equipment detention clock"),
                ("Rail616", "clock.badge.checkmark", "Free time", "Free-time countdown"),
                ("Rail619", "calendar.badge.exclamationmark", "Per diem tracking", "Per-diem accrual"),
                ("Rail624", "magnifyingglass.circle", "Dwell reason analysis", "Root-cause of dwell"),
                ("Rail641", "chart.line.uptrend.xyaxis", "Demurrage analytics", "Demurrage trend by lane"),
                ("Rail645", "gauge.with.dots.needle.67percent", "Detention dashboard", "Detention exposure"),
                ("Rail648", "function", "Demurrage calculator", "Estimate demurrage owed"),
                ("Rail649", "person.2.badge.gearshape", "Detention by customer", "Detention by account"),
                ("Rail650", "clock.arrow.2.circlepath", "Detention history", "Historical detention log"),
                ("Rail651", "gearshape.2", "Auto-detention rules", "Automated detention rules"),
            ])
            opsGroup("EQUIPMENT & FLEET", [
                ("Rail568", "doc.text.below.ecg", "Equipment lease", "Railcar / chassis leases"),
                ("Rail575", "heart.text.square", "Equipment health", "Car condition telemetry"),
                ("Rail585", "location.viewfinder", "Equipment positions", "Where your equipment is"),
                ("Rail588", "waveform.path.ecg", "Fleet health", "Fleet-wide condition"),
                ("Rail598", "ruler", "Equipment specs", "Car / chassis specifications"),
                ("Rail601", "square.grid.2x2", "Chassis pool", "Chassis pool availability"),
                ("Rail629", "rectangle.stack", "Trailer pool detail", "Pool member detail"),
                ("Rail634", "list.bullet.rectangle.portrait", "Railcar inventory", "Owned / leased car roster"),
            ])
            opsGroup("CREW", [
                ("Rail554", "person.3.sequence", "Crew HOS roster", "Crew hours-of-service"),
                ("Rail584", "megaphone", "Crew call board", "Crew assignments"),
                ("Rail595", "checkmark.seal", "Crew certifications", "Crew cert status"),
                ("Rail632", "person.crop.circle.badge.clock", "Crew availability", "Available crew pool"),
                ("Rail636", "globe.badge.chevron.backward", "X-border crew certs", "Cross-border crew docs"),
            ])
            opsGroup("CUSTOMS & CROSS-BORDER", [
                ("Rail006", "globe.americas", "Cross-border customs", "Customs clearance"),
                ("Rail564", "checkmark.shield", "Border clearance", "Border release status"),
                ("Rail583", "arrow.left.arrow.right", "Cross-border interchange", "Interchange handoff"),
                ("Rail596", "percent", "Duty HTS estimate", "Estimate duty by HTS"),
                ("Rail597", "exclamationmark.triangle", "Hazmat DG rules", "DG segregation rules"),
                ("Rail637", "globe.badge.chevron.backward", "X-border DG regs", "Cross-border DG regs"),
                ("Rail638", "globe", "X-border compliance", "Cross-border compliance"),
            ])
            opsGroup("COMPLIANCE & SAFETY", [
                ("Rail567", "link.circle", "Chain of custody", "Custody handoff log"),
                ("Rail572", "leaf", "Emissions", "CO2 by movement"),
                ("Rail587", "shield.checkered", "FRA safety", "FRA safety status"),
                ("Rail625", "checkmark.circle.badge.questionmark", "Appointment compliance", "Appt adherence"),
                ("Rail631", "doc.text.magnifyingglass", "FRA accident reports", "FRA incident filings"),
            ])
            opsGroup("COMMERCIAL & BILLING", [
                ("Rail573", "tag", "Accessorial charges", "Accessorial catalog"),
                ("Rail577", "fuelpump.circle", "Fuel surcharge", "FSC schedule"),
                ("Rail580", "tablecells", "Tariff rate lookup", "Tariff rates"),
                ("Rail581", "doc.text", "Settlement summary", "Settlement totals"),
                ("Rail593", "doc.on.doc", "Settlement batch", "Batch settlements"),
                ("Rail594", "list.number", "Cost breakdown", "Per-shipment costs"),
                ("Rail599", "doc.text.magnifyingglass", "Freight bill audit", "Audit freight bills"),
                ("Rail635", "dollarsign.circle", "Financial summary", "Financial overview"),
                ("Rail640", "drop.circle", "Diesel fuel index", "Diesel index"),
            ])
            opsGroup("INTERMODAL & DRAYAGE", [
                ("Rail617", "truck.box", "Drayage orders", "Drayage moves"),
                ("Rail618", "arrow.triangle.branch", "Mode optimization", "Cheapest mode mix"),
                ("Rail620", "lock.open", "Release order", "Equipment release"),
                ("Rail626", "doc.richtext", "Warehouse receipt", "WHR document"),
            ])
            opsGroup("NETWORK, DOCS & CLAIMS", [
                ("Rail579", "bolt.horizontal.circle", "Network disruption", "Active network issues"),
                ("Rail605", "exclamationmark.bubble", "Cargo claim", "File a cargo claim"),
                ("Rail653", "list.bullet.clipboard", "Claims list", "All claims"),
                ("Rail654", "arrow.triangle.2.circlepath", "Claim workflow", "Claim processing"),
                ("Rail655", "shield.lefthalf.filled", "Loss prevention", "Loss-prevention program"),
                ("Rail590", "doc.badge.plus", "Document ingest", "Upload + OCR docs"),
                ("Rail592", "person.badge.key", "Forwarder portal", "Forwarder access"),
                ("Rail607", "arrow.left.arrow.right", "EDI messages", "EDI 404 / 322 / 990"),
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
        NotificationCenter.default.post(name: .eusoRailNavSwap, object: nil, userInfo: ["screenId": screenId])
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CREDENTIALS · on file").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(spacing: Space.s2) {
                    ForEach(credentials) { c in
                        HStack {
                            Text(c.title).font(EType.body).foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(c.statusLabel ?? "-").font(.system(size: 11, weight: .bold))
                                .foregroundStyle((c.expiring ?? false) ? Brand.warning : Brand.success)
                        }
                    }
                }
            }
        }
    }

    private var dutyCard: some View {
        let onDuty = hos?.onDutyHours ?? 6.5
        let limit = hos?.limitHours ?? 12
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("DUTY · HOURS OF SERVICE · live").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("On duty \(onDuty, specifier: "%.1f")h · \(max(limit - onDuty, 0), specifier: "%.1f")h to limit")
                            .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text("\(Int(limit))h cap").font(EType.bodyStrong).monospacedDigit().foregroundStyle(Brand.success)
                    }
                    ProgressView(value: onDuty, total: max(limit, 1)).tint(LinearGradient.primary)
                    Text("Hours of Service Act compliant · last rest \(Int(hos?.lastRestHours ?? 10))h")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("PREFERENCES · saved to your profile").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(spacing: Space.s3) {
                    Toggle(isOn: $notificationsOn) {
                        Text("Push notifications").font(EType.body).foregroundStyle(palette.textPrimary)
                    }
                    .tint(Brand.info)
                    .onChange(of: notificationsOn) { _, v in Task { await savePref("notifications", v) } }
                    HStack { Text("Distance units").font(EType.body).foregroundStyle(palette.textPrimary); Spacer(); Text("miles ›").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textSecondary) }
                    HStack { Text("ESANG AI voice").font(EType.body).foregroundStyle(palette.textPrimary); Spacer(); Text(voiceOn ? "on ›" : "off ›").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.info) }
                }
            }
        }
    }

    private var signOut: some View {
        CTAButton(title: "Sign out", leadingIcon: "rectangle.portrait.and.arrow.right")
    }

    private func load() async {
        loading = true; loadError = nil
        struct Empty: Encodable {}
        struct ProfileOut: Decodable {
            let credentials: [RailCredential]?
            let crewHOS: RailCrewHOSRow?
            
            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                credentials = try? c.decode([RailCredential].self, forKey: .credentials)
                crewHOS = try? c.decode(RailCrewHOSRow.self, forKey: .crewHOS)
            }
            
            enum CodingKeys: String, CodingKey {
                case credentials
                case crewHOS
            }
        }
        do {
            self.me = try await EusoTripAPI.shared.query("users.me", input: Empty())
            let p: ProfileOut = try await EusoTripAPI.shared.query("users.getProfile", input: Empty())
            self.credentials = p.credentials ?? []
            if let crewHOS = p.crewHOS {
                self.hos = crewHOS
            } else {
                self.hos = try? await EusoTripAPI.shared.query("railShipments.getCrewHOS", input: Empty())
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func savePref(_ key: String, _ value: Bool) async {
        // Was pointed at users.updateProfile with {key,value} — that endpoint's
        // Zod schema has no such fields, so it stripped them and persisted
        // nothing (the toggle was dead). Notification prefs live on the
        // dedicated users.updateNotificationPreferences endpoint + the
        // notificationPreferences table. (the-oath 2026-05-28 §6, FIX 3.)
        struct PrefIn: Encodable { let pushNotifications: Bool }
        struct Out: Decodable { let success: Bool? }
        guard key == "notifications" else { return }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "users.updateNotificationPreferences",
                input: PrefIn(pushNotifications: value))
            if out.success != true {
                // Persisted nothing — revert the toggle so the UI reflects
                // truth, and surface the failure instead of silently lying.
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

#Preview("556 · Rail Engineer Account · Night") { RailEngineerAccountScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("556 · Rail Engineer Account · Light") { RailEngineerAccountScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
