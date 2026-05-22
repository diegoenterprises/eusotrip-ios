//
//  DL101_DriverBackhaulDVIROctet.swift
//  EusoTrip — Driver · Backhaul tender + Pretrip DVIR octet (DL101-DL108).
//
//  Pixel-match to:
//    101 Driver Backhaul Offer.svg            (tender)
//    102 Driver Backhaul Accepted.svg         (awarded)
//    103 Driver Pretrip DVIR Started.svg      (0/14)
//    104 Driver Pretrip DVIR Section 3 Ack    (3/14)
//    105 Driver Pretrip DVIR Section 4 Ack    (4/14)
//    106 Driver Pretrip DVIR Section 5 Ack    (5/14)
//    107 Driver Pretrip DVIR Section 6 Ack    (6/14)
//    108 Driver Pretrip DVIR Section 7 Ack    (7/14 · 50%)
//
//  101/102 share BackhaulBody (loads.getById).
//  103-108 share DVIRBody (loads.getById + inspections.getDVIRHistory).
//  Bottom nav frozen.
//

import SwiftUI

// MARK: - Live context

private struct BHLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let trailerType: String?
    let cargoType: String?
    let rate: String?
    let distance: Double?
    let deadheadMiles: Double?
    let pickupDate: String?
}

private struct DVIRSessionRow: Decodable, Hashable {
    let id: Int?
    let status: String?
    let createdAt: String?
    let unitNumber: String?
    let make: String?
    let model: String?
}

// MARK: - Shared shell

private struct DLOctetShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Trips", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct BHKpi {
    let label: String, value: String, subtitle: String, color: Color
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Backhaul body (101/102)
// MARK: ─────────────────────────────────────────────────────────

private struct BackhaulBody: View {
    let loadId: String
    let eyebrow: String
    let citation: String
    let title: String
    let pillCopy: String
    let kpis: (BHLoadCtx?) -> [BHKpi]
    let nextStep: String
    /// Only the DL101 tender screen shows accept/decline actions.
    var showTenderActions: Bool = false

    @Environment(\.palette) private var palette
    @State private var load: BHLoadCtx?
    @State private var actionInFlight: String? = nil
    @State private var actionAck: String?
    @State private var actionError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                pill
                identityRow
                kpiGrid
                nextStepCard
                if showTenderActions { tenderActionRow }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            if let l = load {
                Text("\(l.loadNumber ?? "LD-\(l.id ?? 0)") · \(l.pickupCity ?? "—") → \(l.destCity ?? "—")")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var pill: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("RM").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aurora Freight Lines · Renée Marquette").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("USDOT 3 482 119 · MC-942 008 · Cedar Rapids IA").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis(load).enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.color)
                    Text(k.subtitle).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.color.opacity(0.3)))
            }
        }
    }

    private var nextStepCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(nextStep).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var tenderActionRow: some View {
        HStack(spacing: 10) {
            Button { Task { await acceptTender() } } label: {
                HStack(spacing: 6) {
                    if actionInFlight == "accept" { ProgressView().tint(.white).scaleEffect(0.8) }
                    Text(actionInFlight == "accept" ? "Accepting…" : "Accept tender")
                        .font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(actionInFlight != nil)

            Button { Task { await declineTender() } } label: {
                HStack(spacing: 6) {
                    if actionInFlight == "decline" { ProgressView().scaleEffect(0.8) }
                    Text(actionInFlight == "decline" ? "Declining…" : "Decline")
                        .font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(palette.textPrimary)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.4)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(actionInFlight != nil)
        }
    }

    private func acceptTender() async {
        actionInFlight = "accept"; actionAck = nil; actionError = nil
        defer { actionInFlight = nil }
        struct In: Encodable { let loadId: String }
        struct Out: Decodable { let success: Bool?; let loadId: String?; let acceptedAt: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation("dispatchRole.acceptLoad", input: In(loadId: loadId))
            if resp.success == true {
                actionAck = "Backhaul tender accepted · LD-\(resp.loadId ?? loadId) locked · DVIR opens 60m before pickup."
                await loadCtx()
            } else {
                actionError = "Accept returned no success flag — reload and try again."
            }
        } catch let err {
            actionError = (err as? LocalizedError)?.errorDescription ?? "Accept failed: \(err)"
        }
    }

    private func declineTender() async {
        actionInFlight = "decline"; actionAck = nil; actionError = nil
        defer { actionInFlight = nil }
        struct In: Encodable { let loadId: String; let reason: String? }
        struct Out: Decodable { let success: Bool?; let loadId: String?; let declinedAt: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatchRole.declineLoad",
                input: In(loadId: loadId, reason: "Driver declined backhaul tender via DL101")
            )
            if resp.success == true {
                actionAck = "Backhaul tender declined · returned to Aurora's pool."
                await loadCtx()
            } else {
                actionError = "Decline returned no success flag — reload and try again."
            }
        } catch let err {
            actionError = (err as? LocalizedError)?.errorDescription ?? "Decline failed: \(err)"
        }
    }

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: DVIR body (103-108)
// MARK: ─────────────────────────────────────────────────────────

private struct DVIRBody: View {
    let loadId: String
    let eyebrow: String
    let citation: String
    let sectionsCompleted: Int       // 0 / 3 / 4 / 5 / 6 / 7
    let elapsedSinceAccept: String   // "0:00" / "1:02" / "5:10"

    @Environment(\.palette) private var palette
    @State private var load: BHLoadCtx?
    @State private var dvir: DVIRSessionRow?

    private var sectionTotal: Int { 14 }
    private var progressPct: Double { Double(sectionsCompleted) / Double(sectionTotal) }
    private var stateLabel: String { sectionsCompleted == 0 ? "IN PROGRESS" : "ADVANCING" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                citationPill
                progressCard
                identityRow
                kpiGrid
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task {
            await loadCtx()
            await loadDvir()
        }
        .refreshable { await loadCtx(); await loadDvir() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(sectionsCompleted == 0 ? "Pretrip DVIR · started"
                                        : "Section \(sectionsCompleted) · acked")
                .font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            if let l = load {
                Text("\(l.loadNumber ?? "LD-\(l.id ?? 0)") · \(l.pickupCity ?? "—") → \(l.destCity ?? "—")")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var citationPill: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("§302 ACCEPTED · DVIR \(stateLabel) · \(sectionsCompleted)/14 SECTIONS · \(elapsedSinceAccept) SINCE ACCEPT")
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var progressCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("DVIR PROGRESS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(sectionsCompleted)/14 sections").font(.caption2).foregroundStyle(palette.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(palette.bgPage).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient.diagonal)
                            .frame(width: max(8, geo.size.width * progressPct), height: 8)
                    }
                }
                .frame(height: 8)
                if let d = dvir {
                    Text("Live session · \(d.unitNumber ?? "unit") · \((d.make ?? "") + " " + (d.model ?? ""))")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                } else {
                    Text("No live DVIR row yet · session ID issued on first ack.")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("RM").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aurora Freight Lines · Renée Marquette").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("USDOT 3 482 119 · MC-942 008 · Cedar Rapids IA").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let payout = load?.rate ?? "—"
        let kpis: [BHKpi] = [
            .init(label: "PAYOUT", value: "$\(payout)", subtitle: "NET-30 LOCKED", color: .green),
            .init(label: "RPM",    value: "$5.38",     subtitle: "\(Int(load?.distance ?? 372)) mi LOCKED", color: .blue),
            .init(label: "PICKUP", value: pickupCountdown(), subtitle: "04:00 MST", color: .orange),
            .init(label: "DVIR",   value: "\(sectionsCompleted)/14", subtitle: stateLabel.lowercased(), color: sectionsCompleted == 7 ? .green : .blue),
        ]
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.color)
                    Text(k.subtitle).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.color.opacity(0.3)))
            }
        }
    }

    private var nextStepCard: some View {
        let copy: String = {
            switch sectionsCompleted {
            case 0: return "Walk-around starting. Section 1 (front exterior) is up first."
            case 3: return "Sections 1-3 cleared. Continue to lights + reflectors (S4)."
            case 4: return "Lights/reflectors logged. Tires + wheels (S5) next."
            case 5: return "Tires + wheels passed. Coupling devices (S6) next."
            case 6: return "Coupling cleared. Cargo securement (S7) next — 50% midpoint."
            case 7: return "50% midpoint passed. Cab interior + brakes (S8) up next."
            default: return "Continue walk-around per §392."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pickupCountdown() -> String {
        // Match SVG copy roughly to elapsed-since-accept; pickup window is
        // 14h from accept and counts down 1h per section in the SVGs.
        switch sectionsCompleted {
        case 0: return "14h 18m"
        case 3: return "13h 10m"
        case 4: return "12h 08m"
        case 5: return "11h 06m"
        case 6: return "10h 04m"
        case 7: return "9h 02m"
        default: return "—"
        }
    }

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
    private func loadDvir() async {
        struct In: Encodable { let vehicleId: Int?; let limit: Int }
        do {
            let rows: [DVIRSessionRow] = try await EusoTripAPI.shared.query(
                "inspections.getDVIRHistory",
                input: In(vehicleId: nil, limit: 1)
            )
            dvir = rows.first
        } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: DL101 Backhaul Offer (tender)
// MARK: ─────────────────────────────────────────────────────────

struct DriverBackhaulOfferScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        DLOctetShell(theme: theme) {
            BackhaulBody(
                loadId: loadId,
                eyebrow: "DRIVER · OFFER · BACKHAUL · 53' REEFER",
                citation: "§297 · BACKHAUL TENDER · CARRIER-DISPATCHED · NEXT-CHAIN PORT 1/N",
                title: "Tender · 8m",
                pillCopy: "LD-BH7C3A · PHX-LA · 372 mi · 0 deadhead · 9h HOS · ACCEPT IN 8m",
                kpis: { l in [
                    .init(label: "RATE", value: "$\(l?.rate ?? "2,300")", subtitle: "line haul + FSC", color: .green),
                    .init(label: "PER MILE", value: "$5.38", subtitle: "+8.7% vs avg", color: .green),
                    .init(label: "HOS", value: "9h", subtitle: "post 10h reset", color: .blue),
                    .init(label: "DEADHEAD", value: "0 mi", subtitle: "at origin now", color: .green),
                ] },
                nextStep: "Tender expires in 8 minutes. Accept to lock the chain, decline to release back to Aurora.",
                showTenderActions: true
            )
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: DL102 Backhaul Accepted
// MARK: ─────────────────────────────────────────────────────────

struct DriverBackhaulAcceptedScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        DLOctetShell(theme: theme) {
            BackhaulBody(
                loadId: loadId,
                eyebrow: "DRIVER · TRIPS · BACKHAUL · ACCEPTED",
                citation: "§302 · BACKHAUL TENDER · CARRIER-DISPATCHED · NEXT-CHAIN PORT 5/N",
                title: "Tender accepted",
                pillCopy: "§302 ACCEPTED · 0:00 AGO · 4:00 LEFT ON WINDOW · DISPATCH LOCKED",
                kpis: { l in [
                    .init(label: "PAYOUT", value: "$\(l?.rate ?? "2,128")", subtitle: "NET-30 to ME", color: .green),
                    .init(label: "RPM",    value: "$5.38", subtitle: "\(Int(l?.distance ?? 372)) mi · +8.7%", color: .blue),
                    .init(label: "PICKUP", value: "14h 18m", subtitle: "04:00 MST", color: .orange),
                    .init(label: "HOS",    value: "9h",   subtitle: "post 10h reset", color: .blue),
                ] },
                nextStep: "DVIR opens 60 minutes before pickup. ESang queues the pretrip checklist on your watch."
            )
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: DL103-DL108 DVIR section-ack screens
// MARK: ─────────────────────────────────────────────────────────

struct DriverDVIRStartedScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        DLOctetShell(theme: theme) {
            DVIRBody(
                loadId: loadId,
                eyebrow: "DRIVER · TRIPS · BACKHAUL · DVIR",
                citation: "§306 · BACKHAUL DVIR · PICKUP-STAGE FORERUNNER · NEXT-CHAIN PORT 9/N",
                sectionsCompleted: 0,
                elapsedSinceAccept: "0:06"
            )
        }
    }
}

struct DriverDVIRSection3Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DLOctetShell(theme: theme) {
            DVIRBody(loadId: loadId,
                     eyebrow: "DRIVER · TRIPS · BACKHAUL · DVIR · S3",
                     citation: "§310 · BACKHAUL DVIR · WITHIN-TRACK SECTION-3-ACK · NEXT-CHAIN PORT 13/N",
                     sectionsCompleted: 3, elapsedSinceAccept: "1:02")
        }
    }
}

struct DriverDVIRSection4Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DLOctetShell(theme: theme) {
            DVIRBody(loadId: loadId,
                     eyebrow: "DRIVER · TRIPS · BACKHAUL · DVIR · S4",
                     citation: "§311 · BACKHAUL DVIR · WITHIN-TRACK SECTION-4-ACK · NEXT-CHAIN PORT 14/N",
                     sectionsCompleted: 4, elapsedSinceAccept: "2:04")
        }
    }
}

struct DriverDVIRSection5Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DLOctetShell(theme: theme) {
            DVIRBody(loadId: loadId,
                     eyebrow: "DRIVER · TRIPS · BACKHAUL · DVIR · S5",
                     citation: "§312 · BACKHAUL DVIR · WITHIN-TRACK SECTION-5-ACK · NEXT-CHAIN PORT 15/N",
                     sectionsCompleted: 5, elapsedSinceAccept: "3:06")
        }
    }
}

struct DriverDVIRSection6Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DLOctetShell(theme: theme) {
            DVIRBody(loadId: loadId,
                     eyebrow: "DRIVER · TRIPS · BACKHAUL · DVIR · S6",
                     citation: "§313 · BACKHAUL DVIR · WITHIN-TRACK SECTION-6-ACK · NEXT-CHAIN PORT 16/N",
                     sectionsCompleted: 6, elapsedSinceAccept: "4:08")
        }
    }
}

struct DriverDVIRSection7Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DLOctetShell(theme: theme) {
            DVIRBody(loadId: loadId,
                     eyebrow: "DRIVER · TRIPS · BACKHAUL · DVIR · S7",
                     citation: "§314 · BACKHAUL DVIR · WITHIN-TRACK SECTION-7-ACK · NEXT-CHAIN PORT 17/N · 50% MIDPOINT",
                     sectionsCompleted: 7, elapsedSinceAccept: "5:10")
        }
    }
}

// MARK: - Previews

#Preview("101 Offer · Dark")     { DriverBackhaulOfferScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("102 Accepted · Light") { DriverBackhaulAcceptedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("103 DVIR · Dark")      { DriverDVIRStartedScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("104 S3 · Light")       { DriverDVIRSection3Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("105 S4 · Dark")        { DriverDVIRSection4Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("106 S5 · Light")       { DriverDVIRSection5Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("107 S6 · Dark")        { DriverDVIRSection6Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("108 S7 · Light")       { DriverDVIRSection7Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
