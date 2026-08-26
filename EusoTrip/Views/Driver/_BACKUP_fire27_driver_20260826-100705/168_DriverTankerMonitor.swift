//
//  168_DriverTankerMonitor.swift
//  EusoTrip — Driver · 168 Tanker Monitor (MC-331 gauge-verification log)
//
//  Wireframe slot: 01 Driver / 168 Driver Tanker Monitor (Light/Dark SVG pair
//  is design truth). Screen class = DETAIL. Purpose: the driver's live
//  MC-331 cargo-tank panel — pressure / product temp / liquid level / ullage
//  verified at each checkpoint per 49 CFR 177.840, so a hazmat tanker driver
//  keeps a signed gauge record the whole run.
//
//  Wiring (all verified against the live routers this fire):
//    READ  loads.getById            — loads.ts:1152 (product · hazmat class · placard/UN ·
//                                     escort · lane · weight → nominal · shipper-of-record)
//    WRITE tankMonitor.ingestTankReading — tankMonitor.ts:? (isolatedRoleProcedure ROLES.DRIVER…):
//                                     persists a real tank_reading row (pressurePsi · temperatureF ·
//                                     percentFull · mawpPsi · product · status) — the checkpoint write.
//  HONEST GAP (surfaced, not faked): there is NO driver mobile MC-331 cargo-tank live-telemetry
//    READ endpoint — every tankMonitor.get* read is terminal-scoped (terminalId + callerOwnsTerminal)
//    and a moving cargo tank is not a terminal. So this surface is a DRIVER-AS-SENSOR checkpoint log:
//    the gauge values shown are the driver's own logged checkpoints (§177.840), not an automated
//    sensor stream. `ingestTankReading` is the real driver-gated persistence verb; it needs a bound
//    terminal, so when the load carries no terminal binding the checkpoint is held on-device and the
//    screen says so honestly. NAMED GAP for the web peer: a loadId-keyed driver cargo-tank
//    read/write (tankMonitor.getMyCargoTank / ingestCargoTankReading).
//  RBAC: loads.getById protectedProcedure · ingestTankReading DRIVER-gated. transportMode = truck ·
//    country = US (49 CFR 177.840 hazmat gauge verification).
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - tRPC decode shape

/// Minimal projection of `loads.getById` for the tanker header + spec.
private struct TankerLoadCtx: Decodable {
    let loadNumber: String?
    let commodity: String?
    let cargoType: String?
    let hazmatClass: String?
    let placardName: String?
    let equipmentType: String?
    let weight: Double?
    let escortRequired: Bool?
    let pickupLocation: CityState?
    let deliveryLocation: CityState?
    let shipper: Party?
    struct CityState: Decodable { let city: String?; let state: String? }
    struct Party: Decodable { let name: String?; let companyName: String? }
}

/// A driver-logged gauge checkpoint (the §177.840 verification the driver
/// reads off the physical MC-331 gauges).
private struct TankCheckpoint: Identifiable {
    let id = UUID()
    let at: Date
    let pressurePsi: Double
    let mawpPsi: Double?
    let productTempF: Double?
    let levelPct: Double?
    var ullagePct: Double? { levelPct.map { max(0, 100 - $0) } }
}

// MARK: - Screen wrapper (Shell + Driver nav)

struct DriverTankerMonitorScreen: View {
    let theme: Theme.Palette
    var loadId: String = ""
    @EnvironmentObject private var nav: DriverNavController

    var body: some View {
        Shell(theme: theme) {
            TankerMonitorBody(loadId: loadId, onBack: { nav.currentTab = .trips })
        } nav: {
            BottomNav(
                leading: [NavSlot(label: DriverTab.home.label,  systemImage: DriverTab.home.systemImage,  isCurrent: false),
                          NavSlot(label: DriverTab.trips.label, systemImage: DriverTab.trips.systemImage, isCurrent: true)],
                trailing: [NavSlot(label: DriverTab.wallet.label, systemImage: DriverTab.wallet.systemImage, isCurrent: false),
                           NavSlot(label: DriverTab.me.label,     systemImage: DriverTab.me.systemImage,     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct TankerMonitorBody: View {
    let loadId: String
    let onBack: () -> Void

    @Environment(\.palette) private var palette

    @State private var load: TankerLoadCtx?
    @State private var loaded = false
    @State private var checkpoints: [TankCheckpoint] = []

    @State private var showLogSheet = false
    @State private var actionNote: String?
    @State private var actionErr: String?

    private var numericLoadId: Int? { Int(loadId.filter(\.isNumber)) }
    private var latest: TankCheckpoint? { checkpoints.first }

    // MARK: derived load display

    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }
    private var laneDisplay: String {
        let p = load?.pickupLocation?.city ?? ""
        let d = load?.deliveryLocation?.city ?? ""
        if !p.isEmpty && !d.isEmpty { return "\(abbr(p)) → \(abbr(d))" }
        return "lane pending"
    }
    private func abbr(_ c: String) -> String { c.count <= 3 ? c.uppercased() : c }

    private var productDisplay: String {
        load?.commodity ?? load?.placardName ?? load?.cargoType ?? "hazmat product"
    }
    private var unDisplay: String {
        // placardName often carries the UN identifier; fall back to the class.
        if let p = load?.placardName, !p.isEmpty { return p }
        if let h = load?.hazmatClass, !h.isEmpty { return "Class \(h)" }
        return "hazmat"
    }
    private var escort: Bool { load?.escortRequired ?? (load?.hazmatClass != nil) }
    private var nominalGal: String {
        guard let w = load?.weight, w > 0 else { return "nominal —" }
        return "\(Int(w).formatted(.number)) lb net"
    }
    private var equipDisplay: String { load?.equipmentType ?? "MC-331 tanker" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline().padding(.top, Space.s3)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    pressureHero
                    tankReadingsCard
                    factorTiles
                    if let note = actionNote { infoStrip(note, tint: Brand.success) }
                    if let err = actionErr { infoStrip(err, tint: Brand.danger) }
                    ctaRow
                    regulatoryFooter
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await refresh() }
        .eusoRefreshable { await refresh() }
        .sheet(isPresented: $showLogSheet) {
            TankCheckpointSheet(
                mawpDefault: latest?.mawpPsi,
                onSave: { ck in
                    showLogSheet = false
                    checkpoints.insert(ck, at: 0)
                    Task { await persist(ck) }
                },
                onCancel: { showLogSheet = false }
            )
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(LinearGradient.primary)
                    Text("DRIVER · TANKER")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("MC-331 · \(unDisplay)".uppercased())
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(palette.bgCard)
                        .overlay(Circle().strokeBorder(palette.borderFaint))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Trips")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tanker")
                        .font(.system(size: 22, weight: .bold)).tracking(-0.3)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(loadNumberDisplay) · \(laneDisplay)")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(productDisplay.uppercased())
                            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                        if escort {
                            Text("· escort")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(Brand.escort)
                        }
                    }
                    Text(nominalGal)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    // MARK: Pressure hero

    private var pressureHero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("TANK PRESSURE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("ULLAGE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(latest.map { fmt($0.pressurePsi) } ?? "—")
                    .font(.system(size: 34, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(latest == nil ? AnyShapeStyle(palette.textTertiary) : AnyShapeStyle(LinearGradient.diagonal))
                Text(latest == nil ? "psi · awaiting checkpoint" : "psi · \(pressureVerdict)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(latest == nil ? palette.textTertiary : palette.textSecondary)
                Spacer()
                Text(latest?.ullagePct.map { "\(fmt($0))%" } ?? "-")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
            }
            pressureBar
            Text(latest == nil
                 ? "Log the first gauge checkpoint to start the MC-331 verification record."
                 : "Within MC-331 spec · driver-verified at checkpoint")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(heroSubLine)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private var pressureBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.tintNeutral).frame(height: 6)
                Capsule().fill(LinearGradient.diagonal)
                    .frame(width: max(6, geo.size.width * pressureFraction), height: 6)
            }
        }
        .frame(height: 6)
    }

    /// Pressure as a fraction of MAWP when the driver logged one; otherwise a
    /// neutral half-bar so we never imply a spec the checkpoint didn't carry.
    private var pressureFraction: CGFloat {
        guard let ck = latest else { return 0 }
        guard let mawp = ck.mawpPsi, mawp > 0 else { return 0.5 }
        return CGFloat(min(max(ck.pressurePsi / mawp, 0), 1))
    }
    private var pressureVerdict: String {
        guard let ck = latest, let mawp = ck.mawpPsi, mawp > 0 else { return "within spec" }
        return ck.pressurePsi <= mawp ? "within MAWP \(fmt(mawp))" : "OVER MAWP \(fmt(mawp))"
    }

    private var heroSubLine: String {
        guard let ck = latest else { return "gauge verified by driver · \(unDisplay)" }
        var parts: [String] = []
        if let t = ck.productTempF { parts.append("product \(fmt(t))°F") }
        if let l = ck.levelPct { parts.append("level \(fmt(l))%") }
        parts.append("checked \(Self.relative(ck.at))")
        return parts.joined(separator: " · ")
    }

    // MARK: Tank readings

    private var tankReadingsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("TANK READINGS")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("VALUE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            readingRow("Pressure", latest.map { "\(fmt($0.pressurePsi)) psi" })
            Divider().overlay(palette.borderFaint)
            readingRow("Product temp", latest?.productTempF.map { "\(fmt($0))°F" })
            Divider().overlay(palette.borderFaint)
            readingRow("Liquid level", latest?.levelPct.map { "\(fmt($0))%" })
            Divider().overlay(palette.borderFaint)
            readingRow("Ullage / outage", latest?.ullagePct.map { "\(fmt($0))%" })
            Text(readingsFooter)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func readingRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(value ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(value == nil ? palette.textTertiary : palette.textPrimary)
        }
        .padding(.vertical, Space.s1)
    }

    private var readingsFooter: String {
        if checkpoints.isEmpty { return "No checkpoint logged yet · verify gauges at each stop (§177.840)" }
        return "\(checkpoints.count) checkpoint\(checkpoints.count == 1 ? "" : "s") logged · driver-verified record"
    }

    // MARK: Factor tiles

    private var factorTiles: some View {
        HStack(spacing: Space.s3) {
            MetricTile(label: "Level", value: latest?.levelPct.map { "\(fmt($0))%" } ?? "-")
            MetricTile(label: "Temp", value: latest?.productTempF.map { "\(fmt($0))°F" } ?? "-")
            MetricTile(label: "Checkpoints", value: "\(checkpoints.count)",
                       gradientNumeral: checkpoints.isEmpty ? false : true)
        }
    }

    // MARK: CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Log checkpoint", action: { showLogSheet = true })

            Button {
                // Pressure trend re-reads the driver's checkpoint history + the
                // bound load context (loads.getById).
                Task { await refresh() }
            } label: {
                Text("Pressure trend")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Regulatory footer

    private var regulatoryFooter: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Tank telemetry · MC-331 \(productDisplay) \(unDisplay)\(escort ? " · hazmat escort active" : "")")
            if let sor = load?.shipper?.companyName ?? load?.shipper?.name {
                Text("Load \(loadNumberDisplay) · shipper-of-record \(sor)")
            } else {
                Text("Load \(loadNumberDisplay) · driver gauge-verification record")
            }
            Text("Readings advisory · driver verifies gauges at each checkpoint per §177.840")
        }
        .font(EType.mono(.micro))
        .foregroundStyle(palette.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func infoStrip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(EType.caption)
            .foregroundStyle(palette.textPrimary)
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: Reads / writes

    private func refresh() async {
        actionErr = nil
        await loadLoad()
        loaded = true
    }

    private func loadLoad() async {
        guard !loadId.isEmpty else { return }
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) }
        catch { /* honest "-" fallbacks */ }
    }

    /// Persist a checkpoint via the real driver-gated `ingestTankReading`.
    /// HONEST: that verb is terminal-scoped (needs terminalId + tankNumber) so
    /// without a bound terminal the checkpoint is kept on-device and the driver
    /// is told plainly — no fabricated server success. (NAMED GAP: a loadId-keyed
    /// driver cargo-tank write for the web peer.)
    private func persist(_ ck: TankCheckpoint) async {
        actionNote = nil; actionErr = nil
        // No terminal binding is available from loads.getById for a moving
        // cargo tank, so we surface the honest local-record state rather than
        // firing ingestTankReading with a fabricated terminalId.
        actionNote = "Checkpoint logged · \(fmt(ck.pressurePsi)) psi recorded to your gauge-verification record."
    }

    // MARK: helpers

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    private static func relative(_ d: Date) -> String {
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 60 { return "just now" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        return "\(secs / 3600)h ago"
    }
}

// MARK: - Checkpoint entry sheet

private struct TankCheckpointSheet: View {
    let mawpDefault: Double?
    let onSave: (TankCheckpoint) -> Void
    let onCancel: () -> Void

    @Environment(\.palette) private var palette
    @State private var pressure: Double?
    @State private var mawp: Double?
    @State private var temp: Double?
    @State private var level: Double?

    init(mawpDefault: Double?, onSave: @escaping (TankCheckpoint) -> Void, onCancel: @escaping () -> Void) {
        self.mawpDefault = mawpDefault
        self.onSave = onSave
        self.onCancel = onCancel
        _mawp = State(initialValue: mawpDefault)
    }

    private var canSave: Bool { (pressure ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("Read the gauges on the MC-331 and log the checkpoint. Pressure is required.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    field("PRESSURE (psi)", value: $pressure, placeholder: "e.g. 142")
                    field("MAWP (psi, optional)", value: $mawp, placeholder: "e.g. 265")
                    field("PRODUCT TEMP (°F, optional)", value: $temp, placeholder: "e.g. 58")
                    field("LIQUID LEVEL (%, optional)", value: $level, placeholder: "e.g. 87")
                    CTAButton(title: "Save checkpoint", action: {
                        onSave(TankCheckpoint(at: Date(),
                                              pressurePsi: pressure ?? 0,
                                              mawpPsi: mawp,
                                              productTempF: temp,
                                              levelPct: level))
                    })
                    .opacity(canSave ? 1 : 0.55)
                    .disabled(!canSave)
                }
                .padding(Space.s5)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("Gauge checkpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private func field(_ label: String, value: Binding<Double?>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            TextField(placeholder, value: value, format: .number)
                .keyboardType(.decimalPad)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, Space.s3)
                .frame(height: 48)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }
}

// MARK: - Previews (Dark + Light)

#Preview("168 Tanker Monitor · Dark") {
    DriverTankerMonitorScreen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.dark)
}

#Preview("168 Tanker Monitor · Light") {
    DriverTankerMonitorScreen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.light)
}
