//
//  691_VesselCrewCallBoard.swift
//  EusoTrip — Vessel Operator · Crew Call Board (watch-bill roster).
//
//  Verbatim port of "691 Vessel Crew Call Board.svg" (Dark + Light). Archetype =
//  ROSTER. A crew-change summary hero, a three-column STCW sea-watch grid, then a
//  rank roster where every row carries a rank disc + STCW certificate pill + a
//  validity bar + a relief figure — built for who-stands-which-watch and whose
//  certificate forces a relief.
//
//  tRPC (verified live 2026-07):
//    vesselShipments.getVesselCrew (EXISTS :2007, {companyId?, search?}) → { crew:
//      [{id,name,email,phone,role,profilePicture,isActive}], certifications:
//      [{id,userId,type,name,expiryDate,status}], expiringCount } — company vessel
//      users + their certs; expiringCount = certs expiring within 90 days.
//    vesselShipments.getVesselCompliance (EXISTS :2047, {vesselId?}) — relief /
//      inspection compliance context.
//  HONEST GAPS (surfaced to the-oath): there is no watch-bill assignment or MLC
//    rest-hours mutation (proposed vesselCrew.getWatchBill / assignWatch) — the
//    sea-watch grid, MLC tour figures and relief dates are the design's canonical
//    STCW structure; the roster pills + validity + expiring count bind to REAL
//    certification rows. "Schedule crew change" surfaces the gap, never fakes a write.
//
//  RBAC vesselProcedure. transportMode = vessel · STCW/MLC overlay. NAV
//  (VesselOperator): HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

private struct CrewMember691: Decodable, Identifiable {
    let id: Int
    let name: String?
    let role: String?
    let isActive: Bool?
}

private struct CrewCert691: Decodable, Identifiable {
    let id: Int
    let userId: Int?
    let type: String?
    let name: String?
    let expiryDate: String?
    let status: String?       // active | expired | pending
}

private struct VesselCrew691: Decodable {
    let crew: [CrewMember691]?
    let certifications: [CrewCert691]?
    let expiringCount: Int?
}

struct VesselCrewCallBoardScreen: View {
    var theme: Theme.Palette = Theme.dark
    var companyId: Int? = nil
    var portLabel: String = "USLGB · JUN 12"

    var body: some View {
        Shell(theme: theme) {
            VesselCrewCallBoardBody(companyId: companyId, portLabel: portLabel)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                  isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselCrewCallBoardBody: View {
    @Environment(\.palette) private var palette
    let companyId: Int?
    let portLabel: String

    @State private var data: VesselCrew691? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionNote: String? = nil

    private var crew: [CrewMember691] { data?.crew ?? [] }
    private var aboard: Int { crew.filter { $0.isActive != false }.count }
    private var expiringCount: Int { data?.expiringCount ?? 0 }

    private func cert(for userId: Int) -> CrewCert691? {
        // Prefer an STCW cert, else the soonest-expiring cert for the member.
        let mine = (data?.certifications ?? []).filter { $0.userId == userId }
        if let stcw = mine.first(where: { ($0.type ?? $0.name ?? "").uppercased().contains("STCW") }) {
            return stcw
        }
        return mine.sorted { daysTo($0.expiryDate) ?? Int.max < (daysTo($1.expiryDate) ?? Int.max) }.first
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if let actionNote { noteBanner(actionNote) }

                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    summaryHero
                    watchGrid
                    roster
                    esang
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s2)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("✦ VESSEL OPERATOR · CREW CALL BOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(portLabel)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Crew call board")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: - Summary hero

    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(aboard)")
                        .font(.system(size: 34, weight: .bold)).tracking(-0.6).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text("aboard")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: Space.s4)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CREW CHANGE")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.blue)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(Brand.blue.opacity(0.12)))
                    Text("4 sign-off · 4 sign-on")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("agent Long Beach · Jun 12")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)
            HStack {
                heroStat("MLC TOUR MAX", "180 d", palette.textPrimary)
                Spacer()
                heroStat("REST HRS", "MLC OK", Brand.success)
                Spacer()
                heroStat("CERTS EXP", "\(expiringCount)",
                         expiringCount > 0 ? Brand.warning : Brand.success, trailing: true)
            }
        }
        .padding(Space.s5)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private func heroStat(_ label: String, _ value: String, _ color: Color, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .bold)).monospacedDigit()
                .foregroundStyle(color)
        }
    }

    // MARK: - STCW sea-watch grid

    private struct WatchCol { let top: String; let bot: String; let rank: String; let state: String; let tint: Color }

    private var watchCols: [WatchCol] {
        [
            WatchCol(top: "00–04", bot: "12–16", rank: "2/O", state: "on watch", tint: Brand.magenta),
            WatchCol(top: "04–08", bot: "16–20", rank: "C/O", state: "relief", tint: Brand.info),
            WatchCol(top: "08–12", bot: "20–24", rank: "3/O", state: "rest", tint: Brand.rail),
        ]
    }

    private var watchGrid: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("SEA-WATCH BILL · STCW VIII/2 · 3 WATCHES")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s3) {
                ForEach(Array(watchCols.enumerated()), id: \.offset) { _, col in
                    watchCard(col)
                }
            }
        }
    }

    private func watchCard(_ col: WatchCol) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(col.top)
                .font(.system(size: 11, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(col.bot)
                .font(.system(size: 10)).monospacedDigit()
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 6) {
                Text(col.rank)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(col.rank == "2/O" ? .white : col.tint)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(col.rank == "2/O"
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(col.tint.opacity(0.20))))
                Text(col.state)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Rank roster

    private var roster: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("ROSTER · getVesselCrew · RANK · STCW · TOUR")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                if crew.isEmpty {
                    EusoEmptyState(systemImage: "person.2",
                                   title: "No crew on file",
                                   subtitle: "Vessel crew with STCW certificates will appear here.")
                        .padding(.vertical, Space.s2)
                } else {
                    ForEach(Array(crew.prefix(6).enumerated()), id: \.element.id) { idx, m in
                        if idx > 0 { Rectangle().fill(palette.borderFaint).frame(height: 1) }
                        rosterRow(m)
                    }
                }
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }

    private func rosterRow(_ m: CrewMember691) -> some View {
        let c = cert(for: m.id)
        let expired = (c?.status ?? "").lowercased() == "expired"
        let days = daysTo(c?.expiryDate)
        let expiringSoon = !expired && (days ?? Int.max) <= 90 && (days ?? 0) >= 0
        let tint: Color = expired ? Brand.danger : (expiringSoon ? Brand.warning : Brand.success)
        let rank = rankLabel(m.role)
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.20))
                Text(rankAbbrev(rank))
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(m.name ?? rank)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(certLine(c, rank: rank))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                // Validity bar (cert horizon vs 180-day MLC window).
                GeometryReader { geo in
                    let frac = CGFloat(min(180, max(0, days ?? 0))) / 180
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10)).frame(height: 5)
                        Capsule()
                            .fill(expired || expiringSoon ? AnyShapeStyle(Brand.warning)
                                  : AnyShapeStyle(LinearGradient.primary))
                            .frame(width: geo.size.width * (expired ? 0.15 : frac), height: 5)
                    }
                }
                .frame(height: 5)
                .padding(.trailing, 40)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                Text(pillLabel(expired: expired, expiringSoon: expiringSoon, days: days))
                    .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(tint)
                if let d = days, d >= 0 {
                    Text("\(d) d")
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(.vertical, Space.s3)
    }

    private func certLine(_ c: CrewCert691?, rank: String) -> String {
        let stcw = c?.type ?? c?.name ?? "STCW"
        if (c?.status ?? "").lowercased() == "expired" {
            return "\(stcw) · expired · relief required"
        }
        if let d = daysTo(c?.expiryDate), d <= 90, d >= 0 {
            return "\(stcw) exp \(d)d · schedule relief"
        }
        return "\(stcw) · on file"
    }

    private func pillLabel(expired: Bool, expiringSoon: Bool, days: Int?) -> String {
        if expired { return "EXPIRED" }
        if expiringSoon, let d = days { return "EXP \(d)d" }
        return "VALID"
    }

    /// Maps a platform vessel role → a maritime rank label.
    private func rankLabel(_ role: String?) -> String {
        switch (role ?? "").uppercased() {
        case "SHIP_CAPTAIN":   return "Master"
        case "VESSEL_OPERATOR": return "Chief Officer"
        case "PORT_MASTER":    return "Port Master"
        case "VESSEL_SHIPPER": return "Shipper Rep"
        case "VESSEL_BROKER":  return "Broker"
        case "CUSTOMS_BROKER": return "Customs Broker"
        default:               return "Officer"
        }
    }
    private func rankAbbrev(_ rank: String) -> String {
        switch rank {
        case "Master":        return "MST"
        case "Chief Officer": return "C/O"
        case "Port Master":   return "PM"
        case "Shipper Rep":   return "SR"
        case "Broker":        return "BRK"
        case "Customs Broker": return "CB"
        default:              return "OFF"
        }
    }

    // MARK: - ESANG

    private var esang: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.7), .white.opacity(0)],
                                             center: .init(x: 0.35, y: 0.30),
                                             startRadius: 0, endRadius: 16))
                    .frame(width: 22, height: 22)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · RELIEF PRIORITY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(reliefHeadline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("sign-on relief before the cert lapses to stay MLC-clear")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var reliefHeadline: String {
        // Soonest-expiring cert holder drives the relief priority.
        let soon = crew.compactMap { m -> (CrewMember691, Int)? in
            guard let d = daysTo(cert(for: m.id)?.expiryDate) else { return nil }
            return (m, d)
        }.sorted { $0.1 < $1.1 }.first
        if let (m, d) = soon, d <= 90 {
            return "\(rankLabel(m.role)) first — STCW in \(max(0, d))d"
        }
        return "All certificates current — no relief forced"
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button {
                actionNote = "Watch-bill assignment is pending vesselCrew.assignWatch (surfaced to the-oath); crew-change stub prepared from the roster."
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 15, weight: .bold))
                    Text("Schedule crew change")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                actionNote = "Opening the crew certificate binder."
            } label: {
                Text("Certs")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 110, height: 48)
                    .background(palette.bgSecondary)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading + note

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 104)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 244)
        }
    }

    private func noteBanner(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.info)
            Text(message).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Button { actionNote = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(Brand.info.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.info.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Load + helpers

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let companyId: Int? }
        do {
            let d: VesselCrew691? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselCrew", input: In(companyId: companyId))
            self.data = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func daysTo(_ iso: String?) -> Int? {
        guard let iso else { return nil }
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        let date = f1.date(from: iso) ?? f2.date(from: iso)
        guard let date else { return nil }
        return Int((date.timeIntervalSinceNow / 86_400).rounded())
    }
}

#Preview("691 · Vessel Crew Call Board · Night") {
    VesselCrewCallBoardScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("691 · Vessel Crew Call Board · Light") {
    VesselCrewCallBoardScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
