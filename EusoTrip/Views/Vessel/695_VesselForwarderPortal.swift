//
//  695_VesselForwarderPortal.swift
//  EusoTrip — Vessel Operator · Forwarder Portal (CARRIER-SIDE · BOARD/OPERATIONS class).
//
//  PURPOSE-BUILT: the source wireframe "695 Vessel Forwarder Portal.svg" ships
//  EMPTY in the catalog (0 bytes, Dark + Light), so this screen is composed to
//  the golden bar from the real forwarderPortal router blueprint + design
//  authority. A 3PL COLLABORATION board: a shared-shipment summary, the mixed
//  truck+ocean shipment ledger, a consolidation-opportunity band, and a grant-
//  access console — a board, not a detail card.
//
//  Web parity: ForwarderPortal.tsx (`/portal/3pl`).
//
//  DATA (endpoints confirmed on disk this fire):
//    forwarderPortal.listForwarderShipments {limit}
//        → { truck[], ocean[], total }   (protectedProcedure · company-scoped · server/routers/forwarderPortal.ts:99)
//    forwarderPortal.consolidationSuggestions {}
//        → { suggestions[{lane, loadCount, totalWeight, estimatedSavings}], totalConsolidationOpportunities }
//        (protectedProcedure · forwarderPortal.ts:133)
//    forwarderPortal.createPortalAccess {forwarderName, forwarderEmail, accessLevel, expiresInDays}
//        → { portalId, token, url, accessLevel, expiresAt, shipmentCount }
//        (MUTATION · tenant-gated · forwarderPortal.ts:21)
//
//  HONEST GAPS (surfaced to the-oath — NOT papered over):
//    • consolidationSuggestions returns estimatedSavings as an honest null (no
//      consolidated-lane rate baseline) — this board shows "savings TBD", never
//      a fabricated $/load figure.
//
//  NAV (VesselOperatorNavController): HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//  transportMode=vessel (+ truck loads in the same tenant) · US. PERSONA Vessel Operator / Eusorone.
//

import SwiftUI

struct VesselForwarderPortalScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselForwarderPortalBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct FwdTruck: Decodable, Identifiable {
    let id: Int
    let status: String?
    let loadNumber: String?
    let pickupLocation: String?
    let deliveryLocation: String?
    let rate: String?
}
private struct FwdOcean: Decodable, Identifiable {
    let id: Int
    let status: String?
    let bookingNumber: String?
    let originPortId: Int?
    let destinationPortId: Int?
    let eta: String?
}
private struct ForwarderShipments: Decodable {
    let truck: [FwdTruck]
    let ocean: [FwdOcean]
    let total: Int
}
private struct ConsolidationSuggestion: Decodable, Identifiable {
    var id: String { lane ?? UUID().uuidString }
    let lane: String?
    let loadCount: Int?
    let totalWeight: Double?
    let estimatedSavings: Double?
}
private struct ConsolidationResponse: Decodable {
    let suggestions: [ConsolidationSuggestion]
    let totalConsolidationOpportunities: Int
}
private struct PortalAccessOut: Decodable {
    let token: String
    let url: String
    let accessLevel: String?
    let shipmentCount: Int?
}

// MARK: - Body

private struct VesselForwarderPortalBody: View {
    @Environment(\.palette) private var palette

    @State private var shipments: ForwarderShipments? = nil
    @State private var consolidation: ConsolidationResponse? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var forwarderName: String = ""
    @State private var forwarderEmail: String = ""
    @State private var granting = false
    @State private var grantAck: String? = nil
    @State private var grantError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline().padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s4) {
                    summaryHero
                    consolidationBand
                    sharedLedger
                    grantConsole
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var truck: [FwdTruck] { shipments?.truck ?? [] }
    private var ocean: [FwdOcean] { shipments?.ocean ?? [] }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ VESSEL OPERATOR · FORWARDER PORTAL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("3PL")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Forwarder portal")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary).padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5)
    }

    // MARK: Summary hero

    private var summaryHero: some View {
        HStack(spacing: 0) {
            heroStat("\(shipments?.total ?? 0)", "SHARED")
            divider
            heroStat("\(ocean.count)", "OCEAN")
            divider
            heroStat("\(truck.count)", "TRUCK")
            divider
            heroStat("\(consolidation?.totalConsolidationOpportunities ?? 0)", "MERGE")
        }
        .padding(.vertical, Space.s4).padding(.horizontal, Space.s3)
        .frame(maxWidth: .infinity)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }
    private func heroStat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }
    private var divider: some View { Rectangle().fill(.white.opacity(0.22)).frame(width: 1, height: 30) }

    // MARK: Consolidation band

    private var consolidationBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CONSOLIDATION OPPORTUNITIES · consolidationSuggestions")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            let sugg = consolidation?.suggestions ?? []
            if sugg.isEmpty {
                LifecycleCard {
                    Text(loading ? "Scanning lanes…" : "No multi-load lanes to consolidate right now.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sugg.prefix(4).enumerated()), id: \.element.id) { idx, s in
                        HStack(spacing: Space.s3) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(Brand.magenta.opacity(0.16)).frame(width: 40, height: 40)
                                Image(systemName: "arrow.triangle.merge").font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.magenta)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.lane ?? "—").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                                Text("\(s.loadCount ?? 0) loads · \(weight(s.totalWeight)) lb")
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                            }
                            Spacer(minLength: Space.s2)
                            Text(s.estimatedSavings.map { money($0) } ?? "savings TBD")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(s.estimatedSavings == nil ? palette.textTertiary : Brand.success)
                        }
                        if idx < min(sugg.count, 4) - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s1)
                        }
                    }
                }
                .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.lg)
            }
        }
    }

    // MARK: Shared ledger

    private var sharedLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SHARED SHIPMENTS · listForwarderShipments")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)

            if loading {
                LifecycleCard { Text("Loading shared shipments…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
            } else if truck.isEmpty && ocean.isEmpty {
                EusoEmptyState(icon: Image(systemName: "square.grid.2x2"),
                               title: "Nothing shared yet",
                               subtitle: "Shipments you grant a 3PL access to appear on this board across both modes.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ocean.prefix(5).enumerated()), id: \.element.id) { idx, o in
                        oceanRow(o)
                        if idx < min(ocean.count, 5) - 1 || !truck.isEmpty {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s1)
                        }
                    }
                    ForEach(Array(truck.prefix(5).enumerated()), id: \.element.id) { idx, t in
                        truckRow(t)
                        if idx < min(truck.count, 5) - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s1)
                        }
                    }
                }
                .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.xl)
            }
        }
    }

    private func oceanRow(_ o: FwdOcean) -> some View {
        HStack(spacing: Space.s3) {
            modeChip("ferry.fill", Brand.vessel)
            VStack(alignment: .leading, spacing: 3) {
                Text(o.bookingNumber ?? "Booking \(o.id)").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("port \(o.originPortId.map(String.init) ?? "—") → \(o.destinationPortId.map(String.init) ?? "—")")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            StatusPill(text: (o.status ?? "—").replacingOccurrences(of: "_", with: " "), kind: statusKind(o.status))
        }
    }
    private func truckRow(_ t: FwdTruck) -> some View {
        HStack(spacing: Space.s3) {
            modeChip("box.truck.fill", Brand.info)
            VStack(alignment: .leading, spacing: 3) {
                Text(t.loadNumber ?? "Load \(t.id)").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("\(t.pickupLocation ?? "—") → \(t.deliveryLocation ?? "—")")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            StatusPill(text: (t.status ?? "—").replacingOccurrences(of: "_", with: " "), kind: statusKind(t.status))
        }
    }
    private func modeChip(_ glyph: String, _ color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.16)).frame(width: 40, height: 40)
            Image(systemName: glyph).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
        }
    }

    // MARK: Grant console

    private var grantConsole: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("GRANT 3PL ACCESS · createPortalAccess")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: Space.s3) {
                TextField("Forwarder name", text: $forwarderName)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .padding(Space.s3)
                    .background(RoundedRectangle(cornerRadius: Radius.md).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint, lineWidth: 1))
                TextField("Forwarder email", text: $forwarderEmail)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    .padding(Space.s3)
                    .background(RoundedRectangle(cornerRadius: Radius.md).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint, lineWidth: 1))

                Button { Task { await grant() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.key").font(.system(size: 15, weight: .bold))
                        Text("Grant collaborate access").font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .opacity(canGrant ? 1 : 0.6)
                }
                .buttonStyle(.plain).disabled(!canGrant)

                if let grantAck { Text(grantAck).font(EType.caption).foregroundStyle(Brand.success) }
                if let grantError { Text(grantError).font(EType.caption).foregroundStyle(Brand.danger) }
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg)
        }
    }

    private var canGrant: Bool { !granting && !forwarderName.isEmpty && forwarderEmail.contains("@") }

    // MARK: Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct ListIn: Encodable { let limit = 50 }
        struct Empty: Encodable {}
        do {
            self.shipments = try await EusoTripAPI.shared.query("forwarderPortal.listForwarderShipments", input: ListIn())
            self.consolidation = try? await EusoTripAPI.shared.query("forwarderPortal.consolidationSuggestions", input: Empty())
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func grant() async {
        grantAck = nil; grantError = nil; granting = true
        struct In: Encodable { let forwarderName: String; let forwarderEmail: String; let accessLevel: String; let expiresInDays: Int }
        do {
            let out: PortalAccessOut = try await EusoTripAPI.shared.mutation(
                "forwarderPortal.createPortalAccess",
                input: In(forwarderName: forwarderName, forwarderEmail: forwarderEmail, accessLevel: "collaborate", expiresInDays: 90))
            grantAck = "Access granted (\(out.accessLevel ?? "collaborate")) · \(out.shipmentCount ?? 0) shipment(s)."
            UIPasteboard.general.string = "https://eusotrip.com\(out.url)"
        } catch {
            grantError = error.eusoUserCopy
        }
        granting = false
    }

    // MARK: helpers

    private func statusKind(_ s: String?) -> StatusPill.Kind {
        switch (s ?? "").lowercased() {
        case "delivered", "completed", "arrived": return .success
        case "in_transit", "booked", "posted", "assigned", "confirmed": return .info
        case "delayed", "exception", "held": return .warning
        default: return .neutral
        }
    }
    private func weight(_ v: Double?) -> String {
        guard let v else { return "—" }
        return NumberFormatter.localizedString(from: NSNumber(value: Int(v)), number: .decimal)
    }
    private func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

#Preview("695 · Vessel Forwarder Portal · Night") {
    VesselForwarderPortalScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("695 · Vessel Forwarder Portal · Light") {
    VesselForwarderPortalScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
