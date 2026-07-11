//
//  004_RailDemurrageDetail.swift
//  EusoTrip — Rail · Shipper · Demurrage Detail (brick 004).
//
//  Verbatim SwiftUI port of "05 Rail/004 Rail Demurrage Detail · Dark" at the
//  golden design-authority bar. SHIPPER MONEY/ledger vantage on one rail block's
//  demurrage exposure: a free-time meter hero (dwell vs allowed), a per-car
//  accrual ledger, a tri-country free-time regime band, a dispute window, and a
//  request-early-release / dispute CTA pair. Mirrors 02 Shipper/227 Settlement.
//
//  Nav: canonical Shipper enum HOME · LOADS · [orb] · WALLET(current) · ME.
//  transportMode = rail · US (BNSF interchange) · USD. Persona shipper-of-record
//  Diego Usoro (DU) / Eusorone Technologies (companyId 1).
//
//  WIRING (web parity client/src/pages/shipper/RailDemurrage.tsx):
//    per-car accrual → railShipments.getRailDemurrage  EXISTS · railShipments.ts:1484
//      ({shipmentId}) → [railDemurrage rows]: freeTimeHours, chargeableHours,
//      ratePerHour, totalCharge, status, placedAt, releasedAt, railcarId.
//    dispute → railDemurrageAuto.createDispute          EXISTS · railDemurrageAuto.ts:264
//      ({confirm:true, demurrageId, reason, notes}) → inserts demurrage_disputes row.
//    Request early release → STUB · named-gap requestEarlyRelease({shipmentId,
//      interchangeId, reason}) — no backing procedure yet (handed to the-oath).
//  Free-time remaining, dwell hours, per-day rate, and projected charge are HONEST
//  derivations from the real row fields (placedAt clock + ratePerHour). The
//  tri-country regime band shows the known regulatory free-time constants
//  (US/CA 48h · MX 24h) — compliance reference, not shipment data.
//  RBAC railProcedure (SHIPPER / ADMIN / SUPER_ADMIN).
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Money parse boundary (MySQL decimal → JSON string)

private struct DemFlex004: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        if let i = try? c.decode(Int.self) { value = Double(i); return }
        value = nil
    }
}

/// One railDemurrage row (per railcar) from getRailDemurrage.
private struct RailDemurrageRow004: Decodable, Identifiable {
    let id: Int
    let shipmentId: Int?
    let railcarId: Int?
    let yardId: Int?
    let placedAt: String?
    let releasedAt: String?
    let freeTimeHours: Int?
    let chargeableHours: Int?
    let ratePerHour: DemFlex004?
    let totalCharge: DemFlex004?
    let status: String?          // accruing | invoiced | paid | disputed | waived
}

// MARK: - Screen wrapper

struct RailDemurrageDetailScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 39044

    var body: some View {
        Shell(theme: theme) { RailDemurrageDetailBody(shipmentId: shipmentId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox",      isCurrent: false)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: true),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailDemurrageDetailBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var rows: [RailDemurrageRow004] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var actionBanner: String? = nil
    @State private var actionIsError = false
    @State private var disputing = false
    @State private var requesting = false

    private let usd: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 0; return f
    }()
    private func money(_ v: Double) -> String { usd.string(from: NSNumber(value: v)) ?? "$0" }

    // MARK: Honest derivations

    private var totalChargeable: Double {
        rows.reduce(0) { $0 + ($1.totalCharge?.value ?? 0) }
    }

    /// Representative (earliest-placed) car for the free-time meter.
    private var lead: RailDemurrageRow004? {
        rows.min { ($0.placedAt ?? "") < ($1.placedAt ?? "") } ?? rows.first
    }

    private func hoursSince(_ iso: String?) -> Double? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return nil }
        return Date().timeIntervalSince(date) / 3600
    }

    private var dwellHours: Double? {
        guard let l = lead else { return nil }
        if let placed = l.placedAt {
            if let rel = l.releasedAt, let ph = hoursOf(placed), let rh = hoursOf(rel) { return max(0, rh - ph) }
            return hoursSince(placed)
        }
        return l.chargeableHours.map(Double.init)
    }
    private func hoursOf(_ iso: String) -> Double? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        return d.map { $0.timeIntervalSince1970 / 3600 }
    }

    private var freeTime: Double { Double(lead?.freeTimeHours ?? 48) }
    private var freeRemaining: Double { max(0, freeTime - (dwellHours ?? 0)) }
    private var ratePerHour: Double { lead?.ratePerHour?.value ?? 0 }
    private var ratePerDay: Double { ratePerHour * 24 }
    private var meterProgress: Double { min(max((dwellHours ?? 0) / max(freeTime, 1), 0), 1) }
    private var accruing: Bool { (dwellHours ?? 0) > freeTime || rows.contains { ($0.status ?? "") == "accruing" } }

    private var statusPillText: String {
        let dwell = Int(dwellHours ?? 0)
        return accruing ? "ACCRUING · \(dwell)H DWELL" : "WITHIN FREE TIME · \(dwell)H"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                backRow
                heroTitle
                IridescentHairline().padding(.top, Space.s3)

                if loading {
                    skeleton.padding(.top, Space.s4)
                } else if let err = loadError {
                    errorCard(err).padding(.top, Space.s4)
                } else {
                    freeTimeMeter.padding(.top, Space.s4)
                    accrualLedger.padding(.top, Space.s5)
                    disputeWindow.padding(.top, Space.s4)
                    regimeBand.padding(.top, Space.s5)
                    if let banner = actionBanner {
                        actionBannerView(banner).padding(.top, Space.s3)
                    }
                    ctaPair.padding(.top, Space.s5)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Top bar / title

    private var topBar: some View {
        HStack {
            Text("✦ SHIPPER · RAIL · DEMURRAGE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("FREE TIME · \(Int(freeTime))H")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(Brand.warning)
        }
    }

    private var backRow: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Demurrage").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, Space.s3)
    }

    private var heroTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(money(totalChargeable)) chargeable")
                .font(.system(size: 32, weight: .bold)).tracking(-0.6).monospacedDigit()
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(subLine)
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(.top, Space.s3)
    }

    private var subLine: String {
        let cars = rows.count
        return "\(cars) car\(cars == 1 ? "" : "s") · BNSF interchange · RAIL-\(shipmentId)"
    }

    // MARK: Free-time meter hero

    private var freeTimeMeter: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("RAIL-\(shipmentId)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(statusPillText)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.warning.opacity(0.2)))
            }

            // dwell vs allowed bar (green used · warning remaining)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0x11151C)).frame(width: w, height: 10)
                    Capsule().fill(Brand.success).frame(width: max(w * meterProgress, 4), height: 10)
                    Rectangle().fill(palette.textPrimary)
                        .frame(width: 2, height: 16)
                        .offset(x: min(w * meterProgress, w - 2))
                }
            }
            .frame(height: 16)
            .padding(.top, Space.s4)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(freeRemaining))h")
                    .font(.system(size: 22, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("free time remaining of \(Int(freeTime))h allowed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, Space.s3)

            Text(crossLine)
                .font(EType.caption).foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s2)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(alignment: .leading) {
            Rectangle().fill(LinearGradient(colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
                                            startPoint: .top, endPoint: .bottom)).frame(width: 3)
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var crossLine: String {
        if accruing { return "In demurrage now · \(money(ratePerDay)) / car / day" }
        return "Crosses into demurrage in ~\(Int(freeRemaining))h · \(money(ratePerDay)) / car / day after"
    }

    // MARK: Per-car accrual ledger

    private var accrualLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ACCRUAL · PER CAR").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(rows.count) car\(rows.count == 1 ? "" : "s")")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            if rows.isEmpty {
                EusoEmptyState(systemImage: "clock.badge.checkmark",
                               title: "No accrual on this block",
                               subtitle: "Demurrage rows appear once cars are placed.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                        carRow(r)
                        if idx < rows.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.leading, Space.s4)
                        }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func carRow(_ r: RailDemurrageRow004) -> some View {
        let charge = r.totalCharge?.value ?? 0
        let chargeable = r.chargeableHours ?? 0
        let kind = statusKind(r.status)
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(kind.color.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "tram.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(kind.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(r.railcarId.map { "Car #\($0)" } ?? "Railcar")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("\(chargeable)h chargeable · \(money(ratePerHour))/hr")
                    .font(EType.mono(.caption)).tracking(0.2).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                Text(kind.label).font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(kind.color)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(kind.color.opacity(0.16)))
                Text(money(charge)).font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(charge > 0 ? Brand.danger : palette.textPrimary)
            }
        }
        .padding(Space.s4)
    }

    private func statusKind(_ s: String?) -> (label: String, color: Color) {
        switch (s ?? "").lowercased() {
        case "accruing":  return ("ACCRUING", Brand.warning)
        case "invoiced":  return ("INVOICED", Brand.info)
        case "paid":      return ("PAID", Brand.success)
        case "disputed":  return ("DISPUTED", Brand.escort)
        case "waived":    return ("WAIVED", Brand.neutral)
        default:          return ("OPEN", palette.textSecondary)
        }
    }

    // MARK: Dispute window

    private var disputeWindow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.info.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.info)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Detention dispute available").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Carrier-caused delay (interchange congestion) is disputable")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: Space.s2)
            Text("30d left").font(.system(size: 11, weight: .heavy)).tracking(0.4).monospacedDigit()
                .foregroundStyle(Brand.info)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Brand.info.opacity(0.18)))
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Tri-country regime band (regulatory reference constants)

    private var regimeBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("FREE-TIME REGIME").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s3) {
                regimeCell("US · 48h free", "$35/hr · USD", active: true)
                regimeCell("CA · 48h free", "$35/hr · CAD", active: false)
                regimeCell("MX · 24h free", "$40/hr · MXN", active: false)
            }
        }
    }

    private func regimeCell(_ title: String, _ sub: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? .white : palette.textPrimary)
            Text(sub).font(.system(size: 9.5, weight: .semibold)).monospacedDigit()
                .foregroundStyle(active ? .white.opacity(0.9) : palette.textSecondary)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(active ? Color.clear : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Action banner + CTA

    private func actionBannerView(_ text: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: actionIsError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(actionIsError ? Brand.danger : Brand.success)
            Text(text).font(EType.caption).foregroundStyle(actionIsError ? Brand.danger : palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background((actionIsError ? Brand.danger : Brand.success).opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder((actionIsError ? Brand.danger : Brand.success).opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: requesting ? "Requesting…" : "Request early release",
                      action: { Task { await requestEarlyRelease() } }, isLoading: requesting)
            Button(action: { Task { await fileDispute() } }) {
                Text(disputing ? "Filing…" : "Dispute")
                    .font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(width: 120, height: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct DemIn: Encodable { let shipmentId: Int }
        do {
            let r: [RailDemurrageRow004] = try await EusoTripAPI.shared.query(
                "railShipments.getRailDemurrage", input: DemIn(shipmentId: shipmentId))
            self.rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func fileDispute() async {
        guard !disputing else { return }
        guard let target = rows.first(where: { ($0.status ?? "") == "accruing" }) ?? rows.first else {
            actionIsError = true; actionBanner = "No demurrage row to dispute."; return
        }
        disputing = true; actionBanner = nil
        struct DisputeIn: Encodable { let confirm: Bool; let demurrageId: Int; let reason: String; let notes: String }
        struct DisputeOut: Decodable { let success: Bool?; let disputeId: Int? }
        do {
            let out: DisputeOut = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.createDispute",
                input: DisputeIn(confirm: true, demurrageId: target.id, reason: "carrier_delay",
                                 notes: "Interchange-congestion delay on RAIL-\(shipmentId); carrier-caused per shipper record."))
            actionIsError = false
            actionBanner = out.disputeId.map { "Dispute #\($0) filed." } ?? "Demurrage dispute filed."
            await load()
        } catch {
            actionIsError = true
            actionBanner = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        disputing = false
    }

    private func requestEarlyRelease() async {
        guard !requesting else { return }
        requesting = true; actionBanner = nil
        // PORT-GAP: requestEarlyRelease is a named-gap STUB — no backing procedure.
        // Propose railDemurrageAuto.requestEarlyRelease({shipmentId,interchangeId,
        // reason})->{requestId} → the-oath. We surface the gap honestly rather than
        // fake a success.
        struct ReleaseIn: Encodable { let shipmentId: Int; let reason: String }
        struct ReleaseOut: Decodable { let requestId: String? }
        do {
            let out: ReleaseOut = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.requestEarlyRelease",
                input: ReleaseIn(shipmentId: shipmentId, reason: "Skip tier-1 demurrage at BNSF interchange."))
            actionIsError = false
            actionBanner = out.requestId.map { "Early-release request \($0) sent." } ?? "Early-release request sent."
        } catch {
            actionIsError = true
            actionBanner = "Early release not yet wired (named gap). "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        requesting = false
    }

    // MARK: Scaffolds

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 124)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 140)
        }
    }

    private func errorCard(_ err: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Previews

#Preview("004 · Rail Demurrage Detail · Night") {
    RailDemurrageDetailScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("004 · Rail Demurrage Detail · Light") {
    RailDemurrageDetailScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
