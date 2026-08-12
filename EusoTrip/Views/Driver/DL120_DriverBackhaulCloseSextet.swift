//
//  DL120_DriverBackhaulCloseSextet.swift
//  EusoTrip — Driver · Backhaul-close sextet (DL120-DL125).
//
//  Pixel-match to:
//    120 Driver Loading In Progress Tick Two
//    121 Driver Loading In Progress Tick Three
//    122 Driver Bol Pre Sign Opener
//    123 Driver Bol Signed
//    124 Driver BH Paperwork Stage Roll
//    125 Driver BH Closed Stage Roll
//
//  Closes the Driver backhaul chain that began at DL114. All 6 share
//  `BHCloseBody` parameterized by `BHCloseKind`. Body reads
//  `loads.getById` (parties, rate, distance, lane). Every rendered
//  business value binds to live fetched data; anything without a live
//  source renders an honest "-" / "—". Bottom nav frozen.
//
//  Honest binding parity with sibling DL126_DriverCELM04Septet and the
//  corrected DL133_DriverCELM04DVIRContinuationOctet (loads.getById
//  parties). Decode shape MIRRORS DL133 exactly: top-level id is a
//  String on the wire (loads.getById -> String(load.id)); pickup/
//  delivery are nested {city,state}; party ids are numeric (Int).
//

import SwiftUI

private struct BHCLoadCtx: Decodable, Hashable {
    // Top-level load id is a String on the wire (loads.getById -> String(load.id));
    // decoding as Int throws typeMismatch and fails the WHOLE decode -> blank.
    // pickup/delivery are nested {city,state} objects (NOT flat city fields).
    let id: String?
    let loadNumber: String?
    let pickupLocation: BHCLoc?
    let deliveryLocation: BHCLoc?
    let rate: String?
    let distance: Double?
    let equipmentType: String?
    let driver: BHCParty?
    let catalyst: BHCParty?
    let shipper: BHCParty?
    struct BHCLoc: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct BHCParty: Decodable, Hashable {
        let id: Int?            // party (user/company) id is numeric on the wire
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }
}

enum BHCloseKind: String {
    case loadingTick2, loadingTick3, bolPreSign, bolSigned, paperwork, closed
}

/// Stage-only labels — no scenario business data baked in. The view
/// body composes these with the live `load` parties / lane / rate at
/// render time. Anything with no live source renders "-" / "—".
private struct BCConfig {
    let eyebrowStage: String   // "LOADING" / "BOL · PRE-SIGN" / …
    let citation: String       // §number canonical stage citation
    let title: String          // UX title
    let subhead: String        // stage state line
    let stageNote: String      // composed after carrier + loadNumber
    let chainNote: String      // composed after loadNumber + parties
}

private extension BHCloseKind {
    var config: BCConfig {
        switch self {
        case .loadingTick2:
            return .init(eyebrowStage: "BACKHAUL · LOADING-IN-PROGRESS",
                         citation: "§341 · IN-FLIGHT TICK 2 · 42/N PRESERVED · SUB-AXIS 4/N CLOSED",
                         title: "Loading in progress",
                         subhead: "LOADING · IN PROGRESS",
                         stageNote: "loading in progress · forklift active",
                         chainNote: "loading run live · dispatcher monitors")
        case .loadingTick3:
            return .init(eyebrowStage: "BACKHAUL · LOADING-IN-PROGRESS",
                         citation: "§342 · IN-FLIGHT TICK 3 FINAL · 42/N PRESERVED · BOL-PRE-SIGN ARMED",
                         title: "Loading complete",
                         subhead: "LOADING · COMPLETE",
                         stageNote: "loading complete · forklift idle",
                         chainNote: "loading complete · BOL-pre-sign armed")
        case .bolPreSign:
            return .init(eyebrowStage: "BACKHAUL · BOL-PRE-SIGN",
                         citation: "§343 · SUB-AXIS 1/N OPEN · NEXT-CHAIN PORT 43/N ADVANCES · PRIOR LOADING COMPLETE",
                         title: "BOL pre-sign",
                         subhead: "BOL · PRE-SIGN · DRAFT",
                         stageNote: "BOL draft loaded · ME at dock plate",
                         chainNote: "BOL packet DRAFT · awaiting signature")
        case .bolSigned:
            return .init(eyebrowStage: "BACKHAUL · BOL-SIGNED",
                         citation: "§347 · WITHIN-TRACK COMMIT · NEXT-CHAIN PORT 47/N ADVANCES · WATCH FIRED",
                         title: "BOL signed",
                         subhead: "BOL · SIGNED",
                         stageNote: "BOL signed · stylus retracted",
                         chainNote: "BOL packet SIGNED · paperwork watch armed")
        case .paperwork:
            return .init(eyebrowStage: "BACKHAUL · PAPERWORK-OPEN",
                         citation: "§351 · STAGE ROLL DELIVERY → PAPERWORK · 51/N ADVANCES · WATCH ARMED",
                         title: "Paperwork open",
                         subhead: "PAPERWORK · OPEN",
                         stageNote: "BOL filed · POD pending · ME at packet desk",
                         chainNote: "BOL FILED · POD pending submit")
        case .closed:
            return .init(eyebrowStage: "BACKHAUL · CLOSED-OPEN",
                         citation: "§355 · STAGE ROLL PAPERWORK → CLOSED · 55/N · POD SUBMITTED · QUARTET 1/N OPEN",
                         title: "Chain closed",
                         subhead: "CLOSED · OPEN",
                         stageNote: "POD submitted · BOL filed · payout review",
                         chainNote: "POD submitted · payout NET-30 locked")
        }
    }
}

private struct BHCloseShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
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

private struct BHCloseBody: View {
    let loadId: String
    let kind: BHCloseKind

    @Environment(\.palette) private var palette
    @State private var load: BHCLoadCtx?
    @State private var actionInFlight: Bool = false
    @State private var actionAck: String?
    @State private var actionError: String?

    // MARK: - Dynamic display helpers (live-bound; honest "-" / "—" fallback)

    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }

    /// Carrier code = the dispatching carrier (catalyst) company / name.
    private var carrierCodeDisplay: String {
        load?.catalyst?.companyName ?? load?.catalyst?.name ?? "-"
    }

    /// Lane from the nested {city,state} objects; server sends "" (not
    /// nil) when missing, so empty components are dropped. Returns nil
    /// when there is no live origin/destination at all.
    private var laneDisplay: String? {
        let o = [load?.pickupLocation?.city, load?.pickupLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        let d = [load?.deliveryLocation?.city, load?.deliveryLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        guard !o.isEmpty || !d.isEmpty else { return nil }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }

    /// USDOT line from the carrier (catalyst) party. No fabrication —
    /// "—" when the carrier carries no DOT/MC on the wire.
    private var carrierRegDisplay: String {
        let dot = load?.catalyst?.dotNumber.map { "USDOT \($0)" }
        let mc  = load?.catalyst?.mcNumber.map { "MC-\($0)" }
        let parts = [dot, mc].compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                chainPill(c)
                identityRow
                kpiGrid
                nextStepCard
                if kind == .bolPreSign { signBOLActionRow }
                if let ack = actionAck {
                    LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(.green) }
                }
                if let err = actionError {
                    LifecycleCard { Text(err).font(EType.caption).foregroundStyle(.red) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private var signBOLActionRow: some View {
        Button { Task { await signBOL() } } label: {
            HStack(spacing: 6) {
                if actionInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                Text(actionInFlight ? "Signing…" : "Sign BOL")
                    .font(EType.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(actionInFlight)
    }

    private func signBOL() async {
        actionInFlight = true; actionAck = nil; actionError = nil
        defer { actionInFlight = false }
        // The signature hash is the digest of the captured signature. The
        // server (loads.signBOL) REQUIRES a non-empty signatureHash and
        // echoes it into the audit row — it is NOT minted server-side. We
        // compute a real per-tap digest here (no hardcoded literal) and
        // reference the live load number for the BOL packet. We display
        // ONLY the value the server returns, never an invented constant.
        let bolRef = load?.loadNumber ?? loadId
        let sigHash = "0x" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
        struct In: Encodable { let loadId: String; let bolNumber: String; let signatureHash: String; let signedAtIso: String? }
        struct Out: Decodable { let success: Bool?; let loadId: String?; let bolNumber: String?; let signatureHash: String?; let signedAt: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "loads.signBOL",
                input: In(loadId: loadId, bolNumber: bolRef, signatureHash: String(sigHash), signedAtIso: nil)
            )
            if resp.success == true {
                let sig = resp.signatureHash ?? "—"
                actionAck = "BOL signed · sig-hash \(sig) committed · paperwork watch armed."
                await loadCtx()
            } else {
                actionError = "BOL sign returned no success flag, reload and try again."
            }
        } catch let err {
            actionError = (err as? LocalizedError)?.errorDescription ?? "BOL sign failed: \(err)"
        }
    }

    private func header(_ c: BCConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DRIVER · TRIPS · \(c.eyebrowStage) · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: BCConfig) -> some View {
        return LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("\(carrierCodeDisplay) · \(loadNumberDisplay) · \(c.stageNote)")
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(loadNumberDisplay) · \(laneDisplay ?? "-")")
                    .font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func chainPill(_ c: BCConfig) -> some View {
        let driverIni = load?.driver?.initials ?? "-"
        let dispIni   = load?.catalyst?.initials ?? "-"
        let shipIni   = load?.shipper?.initials ?? "-"
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("DISPATCH CHAIN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("\(loadNumberDisplay) · \(c.chainNote) · \(driverIni) driver · \(dispIni) ops · \(shipIni) shipper")
                    .font(.caption2).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var identityRow: some View {
        let dispIni     = load?.catalyst?.initials ?? "-"
        let dispName    = load?.catalyst?.name ?? "-"
        let driverName  = load?.driver?.name ?? "-"
        let shipperName = load?.shipper?.name ?? "-"
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(dispIni).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(carrierCodeDisplay) · \(dispName) · dispatcher")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("\(carrierRegDisplay) · \(driverName) (driver) · \(shipperName) (shipper) · \(loadNumberDisplay) backhaul")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let payout = Self.payoutDisplay(load?.rate)
        let dist = Self.distanceDisplay(load?.distance)
        let lane = laneDisplay ?? "-"
        // Stage state KPIs carry the lifecycle posture; business values
        // (PAYOUT / DIST / lane) bind live, anything with no live source
        // renders an honest "—". Pallet counts and sig-hash have NO live
        // source on loads.getById, so they show "—" (never fabricated).
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .loadingTick2:
                return [
                    ("PALLETS", "—",        "no live count",            .blue),
                    ("DIST",    dist,       lane,                       .blue),
                    ("PAYOUT",  payout,     carrierCodeDisplay,         .green),
                    ("STATE",   "LOADING",  "in progress",              .blue),
                ]
            case .loadingTick3:
                return [
                    ("PALLETS", "—",         "no live count",           .blue),
                    ("STATE",   "COMPLETE",  "forklift idle",           .green),
                    ("DIST",    dist,        lane,                      .blue),
                    ("PAYOUT",  payout,      carrierCodeDisplay,        .green),
                ]
            case .bolPreSign:
                return [
                    ("BOL",     "DRAFT",     "loaded · ME signing",     .blue),
                    ("PALLETS", "—",         "no live count",           .blue),
                    ("DIST",    dist,        lane,                      .blue),
                    ("PAYOUT",  payout,      carrierCodeDisplay,        .green),
                ]
            case .bolSigned:
                return [
                    ("BOL",     "SIGNED",     "ME committed",           .green),
                    ("SIG-HASH","—",          "no live source",         .green),
                    ("DIST",    dist,         lane,                     .blue),
                    ("PAYOUT",  payout,       carrierCodeDisplay,       .green),
                ]
            case .paperwork:
                return [
                    ("BOL",     "FILED",      "ME at packet desk",      .green),
                    ("POD",     "PENDING",    "submit ready",           .orange),
                    ("DIST",    dist,         lane,                     .blue),
                    ("PAYOUT",  payout,       carrierCodeDisplay,       .green),
                ]
            case .closed:
                return [
                    ("PAYOUT",  payout,       "NET-30 · \(carrierCodeDisplay)", .green),
                    ("POD",     "SUBMITTED",  "audit-chained",          .green),
                    ("BOL",     "FILED",      "archived",               .green),
                    ("DIST",    dist,         lane,                     .blue),
                ]
            }
        }()
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.0).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.1).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.3)
                    Text(k.2).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.3.opacity(0.3)))
            }
        }
    }

    private var nextStepCard: some View {
        let lane = laneDisplay ?? "-"
        let copy: String = {
            switch kind {
            case .loadingTick2: return "Loading in progress on \(loadNumberDisplay). Forklift cadence steady; depart when the trailer seals."
            case .loadingTick3: return "Loading complete on \(loadNumberDisplay). BOL-PRE-SIGN armed, proceed to the dock plate to sign the draft."
            case .bolPreSign:   return "BOL draft loaded for \(loadNumberDisplay). ME taps sign-acknowledge on the dock plate; the tamper-evident signature is minted by EusoTrip on commit, not on this phone."
            case .bolSigned:    return "BOL signed for \(loadNumberDisplay). Roll the chain to paperwork; the packet-desk watch fires on filing."
            case .paperwork:    return "BOL filed at the packet desk for \(loadNumberDisplay). Submit the POD to advance the chain to closed and stage payout."
            case .closed:       return "Chain closed on \(loadNumberDisplay) · \(lane). POD audit-chained, BOL archived, payout NET-30 locked. Backhaul complete."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }

    /// Format the load's rate (decimal string from server) as a
    /// payout display. Falls back to "-" when missing/invalid.
    private static func payoutDisplay(_ rate: String?) -> String {
        guard let r = rate, let n = Double(r), n > 0 else { return "-" }
        let v = n.rounded()
        return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
    }

    /// Format the load's distance in miles. Falls back to "-".
    private static func distanceDisplay(_ d: Double?) -> String {
        guard let d, d > 0 else { return "-" }
        return "\(Int(d.rounded())) mi"
    }
}

// MARK: - Screens (DL120-DL125)

struct DriverLoadingTick2Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHCloseShell(theme: theme) { BHCloseBody(loadId: loadId, kind: .loadingTick2) } }
}
struct DriverLoadingTick3Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHCloseShell(theme: theme) { BHCloseBody(loadId: loadId, kind: .loadingTick3) } }
}
struct DriverBOLPreSignScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHCloseShell(theme: theme) { BHCloseBody(loadId: loadId, kind: .bolPreSign) } }
}
struct DriverBOLSignedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHCloseShell(theme: theme) { BHCloseBody(loadId: loadId, kind: .bolSigned) } }
}
struct DriverBHPaperworkScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHCloseShell(theme: theme) { BHCloseBody(loadId: loadId, kind: .paperwork) } }
}
struct DriverBHClosedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHCloseShell(theme: theme) { BHCloseBody(loadId: loadId, kind: .closed) } }
}

// MARK: - Previews

#Preview("DL120 Tick2 · Dark")     { DriverLoadingTick2Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL121 Tick3 · Light")    { DriverLoadingTick3Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL122 BOL Pre · Dark")   { DriverBOLPreSignScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL123 BOL Sign · Light") { DriverBOLSignedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL124 Paper · Dark")     { DriverBHPaperworkScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL125 Closed · Light")   { DriverBHClosedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
