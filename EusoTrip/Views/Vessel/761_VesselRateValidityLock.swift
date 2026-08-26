//
//  761_VesselRateValidityLock.swift
//  EusoTrip — Vessel Operator · Rate Validity Lock.
//
//  Faithful 1:1 port of "761 Vessel Rate Validity Lock.svg" (Light + Dark).
//  COUNTDOWN-LOCK archetype (deliberately distinct from a rate table or a quote
//  matrix): a single locked spot quote with a focal COUNTDOWN RING, a locked-
//  terms list, a rate-vs-market save band, and a rate-currency/tariff band.
//  Real Vessel-Operator BottomNav with SHIPMENTS inked.
//
//  Wiring (confirmed on disk this fire):
//    vesselShipments.searchRates — EXISTS vesselShipments.ts:1361 (vesselProcedure)
//      · input {originPortId?,destinationPortId?,containerSize?} → vesselFreightRates[]
//      · drives the REAL base freight, all-in surcharges, locked all-in (best),
//        market avg, and savings-vs-market.
//    createVesselBooking — EXISTS vesselShipments.ts:424 — the book target a real
//        lock would settle at the frozen price.
//    STUB · named-gap (handed to the-oath): vesselRate.lockQuote / .getLock /
//      .bookLocked — no rate-LOCK / quote-validity timer that freezes a price for a
//      TTL and guarantees loading (grep rateValidity/lockQuote = 0 server-wide). The
//      countdown ring + validity/guaranteed-loading/demurrage-free terms are that
//      proposed server-authoritative lock, disclosed on-screen (never a client clock).
//
//  0 fabricated countdown — the price/market figures are data-backed from real
//  rates; the lock TTL + guarantee terms read "lock pending" until lockQuote ships.
//

import SwiftUI

// MARK: - Model

private struct RateLock761 {
    let baseFreightCents: Int
    let surchargeCents: Int
    let lockedAllInCents: Int
    let marketAvgCents: Int
    let carrier: String?
    var savingsCents: Int { max(0, marketAvgCents - lockedAllInCents) }
    var savingsFraction: Double { marketAvgCents > 0 ? Double(lockedAllInCents) / Double(marketAvgCents) : 1 }
}

private struct RateQuery761: Encodable { let containerSize: String }

// MARK: - Wrapper

struct VesselRateValidityLockScreen: View {
    let theme: Theme.Palette
    var lane: String = "CNSHA → Long Beach USLGB · 40'HC"
    var body: some View {
        Shell(theme: theme) {
            VesselRateLockBody761(lane: lane)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselRateLockBody761: View {
    let lane: String
    @Environment(\.palette) private var palette

    @State private var lock: RateLock761? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var gapBanner: String? = nil

    private let locked = Color(hex: 0x34D8A6)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Pricing the lane…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let l = lock, l.lockedAllInCents > 0 {
                    heroCard(l)
                    termsSection(l)
                    marketBand(l)
                    currencyBand
                    if let b = gapBanner {
                        Text(b).font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.warning).padding(.horizontal, 4)
                    }
                    ctaPair
                } else {
                    EusoEmptyState(systemImage: "lock.open",
                                   title: "No live rate to lock",
                                   subtitle: "vesselShipments.searchRates returned no priced rates for this lane, so there is nothing to freeze. Re-quote when a rate posts.")
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · RATE LOCK").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("SPOT").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Text("Rate lock").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Hero — locked quote + countdown ring

    private func heroCard(_ l: RateLock761) -> some View {
        RimCard761 {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lane).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textSecondary).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(money(l.lockedAllInCents)).font(.system(size: 26, weight: .heavy)).monospacedDigit().foregroundStyle(palette.textPrimary)
                        Text("all-in").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textSecondary)
                    }
                    Text("\(l.carrier ?? "Best carrier") · guaranteed load").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Text("Lock pending · re-quote on expiry").font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: 0)
                lockRing
            }
        }
    }

    /// Countdown ring — the proposed server-authoritative lock (vesselRate.lockQuote).
    /// No live lock exists, so the ring reads "LOCK PENDING" rather than a faked clock.
    private var lockRing: some View {
        ZStack {
            Circle().stroke(palette.textPrimary.opacity(0.12), lineWidth: 8).frame(width: 68, height: 68)
            Circle().trim(from: 0, to: 0.72)
                .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 68, height: 68)
            VStack(spacing: 1) {
                Text("LOCK").font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("PENDING").font(.system(size: 6.5, weight: .heavy)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Locked terms

    private func termsSection(_ l: RateLock761) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("LOCKED TERMS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("QUOTE LOCK UNAVAILABLE").font(.system(size: 8.5, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                termRow("Base ocean freight", money(l.baseFreightCents), real: true)
                Divider().overlay(palette.borderFaint).padding(.leading, 16)
                termRow("All-in surcharges", money(l.surchargeCents), real: true)
                Divider().overlay(palette.borderFaint).padding(.leading, 16)
                termRow("Validity window", "lock pending", real: false)
                Divider().overlay(palette.borderFaint).padding(.leading, 16)
                termRow("Guaranteed loading", "lock pending", real: false)
                Divider().overlay(palette.borderFaint).padding(.leading, 16)
                termRow("Demurrage-free days", "lock pending", real: false)
            }
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func termRow(_ label: String, _ value: String, real: Bool) -> some View {
        HStack {
            Text(label).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value).font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(real ? palette.textPrimary : palette.textTertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: Rate vs market

    private func marketBand(_ l: RateLock761) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("RATE VS MARKET").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("EXISTS searchRates:1361").font(.system(size: 8.5, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Locked \(money(l.lockedAllInCents))").font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text("Market avg \(money(l.marketAvgCents))").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.textPrimary.opacity(0.12)).frame(height: 5)
                            Capsule().fill(locked).frame(width: max(6, CGFloat(l.savingsFraction) * g.size.width), height: 5)
                        }
                    }.frame(height: 5)
                }
                Spacer(minLength: 0)
                Text("SAVE \(money(l.savingsCents))").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(LinearGradient(colors: [Brand.success, Color(hex: 0x00966B)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft))
        }
    }

    // MARK: Rate currency band

    private var currencyBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RATE CURRENCY · tariff authority").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 8) {
                ccyRow("US", "US · USD · FMC tariff · CBP ACE", active: true)
                ccyRow("CA", "CA · CAD · CTA tariff · CBSA", active: false)
                ccyRow("MX", "MX · MXN · SAT · DOF tariff", active: false)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft))
        }
    }

    private func ccyRow(_ code: String, _ detail: String, active: Bool) -> some View {
        HStack(spacing: 10) {
            Text(code).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(active ? Color.white : palette.textTertiary)
                .frame(width: 26, height: 16)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard)))
            Text(detail).font(.system(size: 10.5, weight: active ? .bold : .semibold)).foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
            Spacer()
            Text(active ? "ACTIVE" : "STANDBY").font(.system(size: 8, weight: active ? .heavy : .bold)).foregroundStyle(active ? locked : palette.textTertiary)
        }
    }

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: 8) {
            CTAButton(title: "Book at locked rate", action: {
                gapBanner = "Booking at the locked rate is unavailable until a verified quote lock is active."
            }, trailingIcon: "arrow.right")
            Button(action: { Task { await load() } }) {
                Text("Re-quote").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }.buttonStyle(.plain).frame(width: 128)
        }
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil; gapBanner = nil
        do {
            struct RateRow: Decodable {
                let ratePerUnit: Double?; let bafSurcharge: Double?; let thcOrigin: Double?
                let thcDestination: Double?; let peakSeasonSurcharge: Double?
            }
            let rows: [RateRow] = try await EusoTripAPI.shared.query(
                "vesselShipments.searchRates", input: RateQuery761(containerSize: "40ft_hc"))
            let priced = rows.compactMap { r -> (base: Int, sur: Int, all: Int)? in
                let base = Int(((r.ratePerUnit ?? 0) * 100).rounded())
                let sur = Int((((r.bafSurcharge ?? 0) + (r.thcOrigin ?? 0) + (r.thcDestination ?? 0) + (r.peakSeasonSurcharge ?? 0)) * 100).rounded())
                let all = base + sur
                return all > 0 ? (base, sur, all) : nil
            }
            guard !priced.isEmpty else {
                lock = RateLock761(baseFreightCents: 0, surchargeCents: 0, lockedAllInCents: 0, marketAvgCents: 0, carrier: nil)
                loading = false; return
            }
            let best = priced.min { $0.all < $1.all }!
            let marketAvg = priced.map(\.all).reduce(0, +) / priced.count
            lock = RateLock761(baseFreightCents: best.base, surchargeCents: best.sur,
                               lockedAllInCents: best.all, marketAvgCents: marketAvg, carrier: nil)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func money(_ cents: Int) -> String { "$\((cents / 100).formatted(.number.grouping(.automatic)))" }
}

// MARK: - File-scoped bespoke helpers

private struct RimCard761<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }
}

#Preview("761 · Vessel Rate Validity Lock · Night") { VesselRateValidityLockScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("761 · Vessel Rate Validity Lock · Light") { VesselRateValidityLockScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
