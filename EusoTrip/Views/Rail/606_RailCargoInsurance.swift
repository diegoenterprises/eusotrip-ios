//
//  606_RailCargoInsurance.swift
//  EusoTrip 2027 · Wireframe surface · production-fidelity port
//  05 Rail · 606 Rail Cargo Insurance (RAIL_ENGINEER carrier-side vantage)
//
//  IN-APP ADAPTATION 2026-06-02. Faithful 1:1 port of the rebuilt
//  "05 Rail/Light-SVG/606 Rail Cargo Insurance.svg" (+ Dark) — a BESPOKE MONEY /
//  COVERAGE LEDGER. SVG owns the LOOK (insured-value hero + deductible-sliver bar,
//  QUOTE-LINES ledger, policy note, Purchase/Clause CTA, file-scoped Ink_606 palette
//  + IridescentHairline_606). iOS owns the FUNCTION: the bespoke body is wrapped in the
//  app `Shell(theme:) { Body } nav: { BottomNav(...) }` so the REAL rail nav navigates
//  (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME), mirroring sibling 578.
//
//  COMPOSITION (element-for-element with the SVG, preserved):
//    topBar      : ✦ RAIL ENGINEER · CARGO INSURANCE + "INS · BNSF" + chevron + title
//    coverHero   : insured value (big tabular) + premium right-offset (no collision) +
//                  a deductible-sliver coverage bar — the signature money hero
//    coverStrip  : insured / rate / certificate
//    ledger      : QUOTE LINES — line-haul + drayage + COI, each a chip + label + mono
//                  sub + status pill clear of the right money; a premium-total line
//    policyNote  : shipper-of-record = signed-in session user + bind terms
//    ctaRow      : Get quote / Purchase cover (primary · two-stage, live procs)
//                  + Clause (secondary)
//
//  WIRING MANIFEST (honest · verified read-only against insurance.ts 2026-06-09):
//    • insurance.getMyPerLoadPolicies EXISTS insurance.ts:1147  (query · live read seam)
//        → on load(), maps the most-recent active per-load policy into the cover model
//          (insured value = coverageAmount, premium, origin›destination quote line,
//          REAL policy-number COI line). Empty array → honest "no policy on file"
//          em-dash state. Error → rendered error note. NEVER an invented certificate.
//    • insurance.getPerLoadQuote     EXISTS insurance.ts:959   (mutation · cargoValue/
//        commodity/coverage/origin/dest) — "Get quote" re-prices the user's own most
//        recent declared inputs (coverage/commodity/lane from their latest policy row).
//    • insurance.purchasePerLoad     EXISTS insurance.ts:1003  (mutation) — binds the
//        fetched quote into a real perLoadInsurancePolicies row + wallet debit; the COI
//        number shown afterwards is the SERVER-minted policyNumber.
//    ZERO-FALLBACK (2026-06-09): live policy / live quote / em-dash. No fabricated
//    CIC-2026-0518 certificate, no $86,000/$142/0.17%/$500 seed.
//    RBAC: protectedProcedure. transportMode RAIL · US (USD; per-load all-risk ICC(A)).
//
//  No retired names, no emoji icons, one eyebrow, one iridescent hairline.
//  — Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - In-app wrapper (REAL Shell + real Rail Engineer bottom nav · slot = SHIPMENTS)

struct RailCargoInsuranceScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailCargoInsurance_606() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data seam (decodes insurance.getMyPerLoadPolicies rows)

private struct EmptyInput: Encodable, Sendable {}

/// One row from insurance.getMyPerLoadPolicies (insurance.ts:1163 map). All optional so a
/// rolling server row shape never crashes the decode; honest empty otherwise.
private struct PerLoadPolicy_606: Decodable, Identifiable {
    let id: String
    let policyNumber: String?
    let coverageAmount: Double?
    let premium: Double?
    let commodityType: String?
    let policyType: String?
    let status: String?
    let origin: String?
    let destination: String?
    let activatedAt: String?
    let expiresAt: String?
}

// MARK: - Model

enum QuoteState_606 { case quoted, ready
    var label: String { self == .quoted ? "QUOTED" : "READY" } }

struct QuoteLine_606: Identifiable {
    let id = UUID()
    let glyph: String
    let tint: Color
    let title: String
    let detail: String     // mono
    let state: QuoteState_606
    let stateColor: Color
    let amount: String     // money or "issued"
}

struct CargoCover_606 {
    let insuredValue: String   // live money or "—"
    let premium: String        // live money or "—"
    let ratePct: String        // live rate or "—"
    let deductible: String     // live money or "—"
    let insuredShort: String   // live short money or "—"
    let certStatus: String     // real policy status or "—"
    let heroTag: String        // commodity/policy tag · "—" until live
    let lines: [QuoteLine_606]
    let premiumTotal: String
    let bindTerms: String

    /// Honest empty cover — every cell an em-dash, no quote lines.
    static let none = CargoCover_606(
        insuredValue: "—", premium: "—", ratePct: "—", deductible: "—",
        insuredShort: "—", certStatus: "—", heroTag: "—",
        lines: [],
        premiumTotal: "—",
        bindTerms: "no policy on file · get a quote to bind ICC(A) cover")
}

// MARK: - View model (single live-read seam -> insurance.getMyPerLoadPolicies)

@MainActor final class InsuranceVM_606: ObservableObject {
    @Published var c: CargoCover_606 = .none
    @Published var isLoading = false
    @Published var error: String?
    /// true once a REAL bound policy has been mapped in; drives the policy-note wording
    /// (bound vs. fresh quote) so the screen never claims a binding it doesn't have.
    @Published var isBound = false
    /// true while a live quote (insurance.getPerLoadQuote result) is on screen —
    /// the CTA then binds it via insurance.purchasePerLoad.
    @Published var hasQuote = false
    @Published var isWorking = false
    @Published var notice: String?

    /// Most-recent policy row — the user's own declared inputs (coverage,
    /// commodity, lane) that a re-quote re-prices. Never invented.
    private var latestRow: PerLoadPolicy_606?
    private var lastQuote: PerLoadQuote_606?

    private let info    = Color(red: 0.129, green: 0.588, blue: 0.953)
    private let success = Color(red: 0.0, green: 0.588, blue: 0.420)

    func load() async {
        isLoading = true; error = nil
        do {
            // insurance.getMyPerLoadPolicies (query, optional input) — limit defaults to 20.
            let rows: [PerLoadPolicy_606] = try await EusoTripAPI.shared.query(
                "insurance.getMyPerLoadPolicies", input: EmptyInput())
            latestRow = rows.first(where: { ($0.status ?? "").lowercased() == "active" }) ?? rows.first
            if let p = latestRow {
                self.c = map(p)
                self.isBound = ((p.status ?? "").lowercased() == "active")
            } else {
                // Honest empty: no per-load policy on file — em-dash ledger.
                self.c = .none
                self.isBound = false
            }
            self.hasQuote = false
        } catch {
            // Honest error: em-dash ledger + rendered error note. Never a
            // fabricated certificate or premium.
            self.c = .none
            self.isBound = false
            self.error = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Map a real per-load policy row into the 606 cover ledger.
    private func map(_ p: PerLoadPolicy_606) -> CargoCover_606 {
        let coverage   = p.coverageAmount ?? 0
        let premiumVal = p.premium ?? 0
        let deductible = coverage * 0.01            // mirrors server: coverage * 0.01
        let rate       = coverage > 0 ? (premiumVal / coverage) * 100 : 0
        let origin     = (p.origin ?? "—").uppercased()
        let dest       = (p.destination ?? "—").uppercased()
        let policyNo   = p.policyNumber ?? "—"
        let kind       = p.policyType ?? "All-risk"

        return .init(
            insuredValue: coverage > 0 ? money(coverage) : "—",
            premium:      premiumVal > 0 ? money(premiumVal) : "—",
            ratePct:      rate > 0 ? String(format: "%.2f%%", rate) : "—",
            deductible:   coverage > 0 ? money(deductible) : "—",
            insuredShort: coverage > 0 ? shortMoney(coverage) : "—",
            certStatus:   ((p.status ?? "").lowercased() == "active") ? "on file" : (p.status ?? "—"),
            heroTag:      (p.commodityType ?? "per-load").uppercased(),
            lines: [
                .init(glyph: "shield.lefthalf.filled", tint: info, title: "\(kind) · line-haul",
                      detail: "\(origin) › \(dest)", state: .quoted, stateColor: info,
                      amount: premiumVal > 0 ? money(premiumVal) : "—"),
                .init(glyph: "doc.text", tint: success, title: "Certificate · COI",
                      detail: policyNo, state: .ready, stateColor: success, amount: "issued")
            ],
            premiumTotal: premiumVal > 0 ? money(premiumVal) : "—",
            bindTerms: "clause ICC(A) · bound · \(expiryNote(p.expiresAt))")
    }

    /// Map a LIVE quote (insurance.getPerLoadQuote result) over the declared
    /// basis row. State = QUOTED; the COI line shows honestly unissued.
    private func mapQuote(_ q: PerLoadQuote_606, basis p: PerLoadPolicy_606) -> CargoCover_606 {
        let coverage = q.coverage ?? (p.coverageAmount ?? 0)
        let total    = q.totalPremium ?? 0
        let rate     = coverage > 0 && total > 0 ? (total / coverage) * 100 : 0
        let origin   = (p.origin ?? "—").uppercased()
        let dest     = (p.destination ?? "—").uppercased()
        let kind     = q.policyType ?? "All-risk"

        return .init(
            insuredValue: coverage > 0 ? money(coverage) : "—",
            premium:      total > 0 ? money(total) : "—",
            ratePct:      rate > 0 ? String(format: "%.2f%%", rate) : "—",
            deductible:   q.deductible.map { money($0) } ?? "—",
            insuredShort: coverage > 0 ? shortMoney(coverage) : "—",
            certStatus:   "quoted",
            heroTag:      (p.commodityType ?? "per-load").uppercased(),
            lines: [
                .init(glyph: "shield.lefthalf.filled", tint: info, title: "\(kind) · line-haul",
                      detail: "\(origin) › \(dest)", state: .quoted, stateColor: info,
                      amount: total > 0 ? money(total) : "—"),
                .init(glyph: "doc.text", tint: info, title: "Certificate · COI",
                      detail: "issues on purchase", state: .quoted, stateColor: info, amount: "—")
            ],
            premiumTotal: total > 0 ? money(total) : "—",
            bindTerms: "clause ICC(A) · binds on purchase · \(validityNote(q.validUntil))")
    }

    /// Primary CTA. Stage 1 (no live quote yet): re-price the user's own most
    /// recent declared inputs via insurance.getPerLoadQuote. Stage 2 (a live
    /// quote is on screen): bind it via insurance.purchasePerLoad — the COI
    /// number rendered afterwards is the server-minted policyNumber.
    func purchase() async {
        guard !isWorking else { return }
        notice = nil
        guard let basis = latestRow, let coverage = basis.coverageAmount, coverage > 0 else {
            // Honest gap: per-load quoting needs declared cargo inputs and no
            // load context is wired to this surface (WIRE-GAP).
            notice = "No declared cargo on file — quote per-load cover from a load first."
            return
        }
        isWorking = true
        do {
            if let q = lastQuote, hasQuote {
                struct PurchaseIn: Encodable {
                    let cargoValue: Double
                    let coverageAmount: Double
                    let deductible: Double
                    let premium: Double
                    let basePremium: Double
                    let hazmatSurcharge: Double
                    let reeferSurcharge: Double
                    let highValueSurcharge: Double
                    let commodityType: String
                    let policyType: String
                    let origin: String
                    let destination: String
                }
                struct PurchaseOut: Decodable { let success: Bool?; let policyNumber: String? }
                let out: PurchaseOut = try await EusoTripAPI.shared.mutation(
                    "insurance.purchasePerLoad",
                    input: PurchaseIn(
                        cargoValue: coverage,
                        coverageAmount: q.coverage ?? coverage,
                        deductible: q.deductible ?? coverage * 0.01,
                        premium: q.totalPremium ?? 0,
                        basePremium: q.premium ?? 0,
                        hazmatSurcharge: q.hazmatSurcharge ?? 0,
                        reeferSurcharge: q.reeferSurcharge ?? 0,
                        highValueSurcharge: q.highValueSurcharge ?? 0,
                        commodityType: basis.commodityType ?? "general",
                        policyType: q.policyType ?? "All-Risk Cargo",
                        origin: basis.origin ?? "",
                        destination: basis.destination ?? ""))
                notice = out.policyNumber.map { "Cover bound · COI \($0)" } ?? "Cover bound"
                lastQuote = nil
                hasQuote = false
                await load()   // re-read: the bound policy + REAL COI render from the server row
            } else {
                struct QuoteIn: Encodable {
                    let cargoValue: Double
                    let commodityType: String
                    let coverageAmount: Double
                    let origin: String
                    let destination: String
                }
                let q: PerLoadQuote_606 = try await EusoTripAPI.shared.mutation(
                    "insurance.getPerLoadQuote",
                    input: QuoteIn(cargoValue: coverage,
                                   commodityType: basis.commodityType ?? "general",
                                   coverageAmount: coverage,
                                   origin: basis.origin ?? "",
                                   destination: basis.destination ?? ""))
                lastQuote = q
                hasQuote = true
                isBound = false
                c = mapQuote(q, basis: basis)
            }
        } catch {
            notice = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        isWorking = false
    }

    // MARK: formatting
    private func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v)) ?? "0")
    }
    private func shortMoney(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if v >= 1_000     { return String(format: "$%.0fK", v / 1_000) }
        return money(v)
    }
    private func expiryNote(_ iso: String?) -> String {
        guard let iso, iso.count >= 10 else { return "effective gate-in" }
        return "expires \(iso.prefix(10))"
    }
    private func validityNote(_ iso: String?) -> String {
        guard let iso, iso.count >= 10 else { return "valid 24h" }
        return "valid until \(iso.prefix(10))"
    }
}

/// insurance.getPerLoadQuote result (insurance.ts:959) — all optional so a
/// rolling server shape never crashes the decode.
private struct PerLoadQuote_606: Decodable {
    let premium: Double?
    let coverage: Double?
    let deductible: Double?
    let hazmatSurcharge: Double?
    let reeferSurcharge: Double?
    let highValueSurcharge: Double?
    let totalPremium: Double?
    let policyType: String?
    let validUntil: String?
}

// MARK: - Palette (file-scoped · preserves the exact 606 look)

private struct Ink_606 {
    let scheme: ColorScheme
    var page:  Color { scheme == .dark ? Color(red: 0.012, green: 0.012, blue: 0.035) : Color(red: 0.914, green: 0.925, blue: 0.945) }
    var card:  Color { scheme == .dark ? Color(red: 0.110, green: 0.129, blue: 0.157) : .white }
    var soft:  Color { scheme == .dark ? Color(red: 0.137, green: 0.157, blue: 0.196) : .white }
    var note:  Color { scheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.04) }
    var text:  Color { scheme == .dark ? Color(red: 0.961, green: 0.961, blue: 0.969) : Color(red: 0.051, green: 0.067, blue: 0.090) }
    var sub:   Color { scheme == .dark ? Color(red: 0.667, green: 0.698, blue: 0.733) : Color(red: 0.322, green: 0.376, blue: 0.427) }
    var faint: Color { scheme == .dark ? Color(red: 0.431, green: 0.463, blue: 0.506) : Color(red: 0.541, green: 0.588, blue: 0.639) }
    var hair:  Color { scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
    var track: Color { scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08) }
    var danger: Color { Color(red: 0.957, green: 0.263, blue: 0.212) }
}

struct RailCargoInsurance_606: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var vm = InsuranceVM_606()
    @State private var showClause = false
    private var ink: Ink_606 { Ink_606(scheme: scheme) }
    private let eusoPrimary  = LinearGradient(colors: [Color(red: 0.078, green: 0.451, blue: 1.0), Color(red: 0.745, green: 0.004, blue: 1.0)], startPoint: .leading, endPoint: .trailing)
    private let eusoDiagonal = LinearGradient(colors: [Color(red: 0.078, green: 0.451, blue: 1.0), Color(red: 0.745, green: 0.004, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                topBar
                if vm.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading cover…").font(.system(size: 11)).foregroundColor(ink.sub)
                    }
                }
                if let err = vm.error {
                    Text(err)
                        .font(.system(size: 11)).foregroundColor(ink.danger)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(ink.danger.opacity(0.10)))
                }
                coverHero
                coverStrip
                ledger
                policyNote
                ctaRow
                if let note = vm.notice {
                    Text(note).font(.system(size: 11, weight: .semibold)).foregroundColor(ink.sub)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .background(ink.page.ignoresSafeArea())
        .foregroundColor(ink.text)
        .task { await vm.load() }
        .eusoRefreshable { await vm.load() }
        .sheet(isPresented: $showClause) {
            clauseSheet
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                EusoTripEyebrow("RAIL ENGINEER · CARGO INSURANCE").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(eusoPrimary)
                Spacer()
                Text("INS · PER-LOAD").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(ink.faint)
            }
            HStack(spacing: 10) {
                Text("Cargo cover").font(.system(size: 28, weight: .bold)).kerning(-0.4)
                Spacer()
            }
            IridescentHairline_606(scheme: scheme)
        }
    }

    private var coverHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ALL-RISK CARGO COVER · ICC(A)").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundColor(ink.faint)
                Spacer()
                Text(vm.c.heroTag).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(ink.faint)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.c.insuredValue).font(.system(size: 30, weight: .bold)).monospacedDigit()
                    Text("insured value · per-load").font(.system(size: 11)).foregroundColor(ink.sub)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("PREMIUM").font(.system(size: 9, weight: .heavy)).kerning(0.6).foregroundColor(ink.faint)
                    Text(vm.c.premium).font(.system(size: 22, weight: .bold)).foregroundStyle(eusoDiagonal).monospacedDigit()
                    Text("\(vm.c.ratePct) rate").font(.system(size: 10)).foregroundColor(ink.sub)
                }
            }.padding(.top, 8)
            ZStack(alignment: .leading) {
                Capsule().fill(ink.track).frame(height: 8)
                GeometryReader { geo in
                    Capsule().fill(eusoPrimary).frame(width: geo.size.width - 12, height: 8).offset(x: 12)
                    Capsule().fill(ink.danger).frame(width: 10, height: 8)
                }.frame(height: 8)
            }.frame(height: 8).padding(.top, 14)
            Text("\(vm.c.deductible) deductible / claim · red sliver = retained risk").font(.system(size: 10)).foregroundColor(ink.faint).padding(.top, 8)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18.5).fill(ink.card))
        .padding(1.5)
        .background(RoundedRectangle(cornerRadius: 20).fill(eusoDiagonal).opacity(scheme == .dark ? 0.95 : 0.85))
    }

    private var coverStrip: some View {
        HStack(spacing: 0) {
            cell("INSURED", vm.c.insuredShort)
            Rectangle().fill(ink.hair).frame(width: 1, height: 30)
            cell("RATE", vm.c.ratePct)
            Rectangle().fill(ink.hair).frame(width: 1, height: 30)
            cell("CERTIFICATE", vm.c.certStatus)
        }
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(ink.card).overlay(RoundedRectangle(cornerRadius: 16).stroke(ink.hair, lineWidth: 1)))
    }
    private func cell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 8, weight: .heavy)).kerning(0.6).foregroundColor(ink.faint)
            Text(value).font(.system(size: 17, weight: .bold)).monospacedDigit()
        }.frame(maxWidth: .infinity)
    }

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("QUOTE LINES").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundColor(ink.faint)
                Spacer()
                Text("policy quote lines").font(.system(size: 11, design: .monospaced)).foregroundColor(ink.sub)
            }.padding(.bottom, 12)
            VStack(spacing: 0) {
                if vm.c.lines.isEmpty {
                    // Honest empty: no per-load policy on file, no quote
                    // fetched — never a fabricated quote line or COI.
                    HStack(spacing: 12) {
                        Image(systemName: "shield.slash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(ink.faint)
                        Text("No policy on file · no quote lines yet")
                            .font(.system(size: 12)).foregroundColor(ink.sub)
                        Spacer()
                    }
                    .padding(16)
                    Divider().overlay(ink.hair)
                }
                ForEach(vm.c.lines) { line in
                    lineRow(line)
                    Divider().overlay(ink.hair).padding(.leading, 84)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Premium total").font(.system(size: 13, weight: .bold))
                        Text(vm.c.bindTerms).font(.system(size: 10)).foregroundColor(ink.faint)
                    }
                    Spacer()
                    Text(vm.c.premiumTotal).font(.system(size: 18, weight: .bold)).monospacedDigit()
                }.padding(16)
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(ink.card).overlay(RoundedRectangle(cornerRadius: 16).stroke(ink.hair, lineWidth: 1)))
        }
    }
    private func lineRow(_ l: QuoteLine_606) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(l.tint.opacity(scheme == .dark ? 0.18 : 0.12)).frame(width: 40, height: 40)
                Image(systemName: l.glyph).font(.system(size: 16, weight: .semibold)).foregroundColor(l.tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(l.title).font(.system(size: 14, weight: .bold))
                Text(l.detail).font(.system(size: 11, design: .monospaced)).kerning(0.4).foregroundColor(ink.sub)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(l.state.label).font(.system(size: 11, weight: .bold)).kerning(0.6).foregroundColor(l.stateColor)
                Text(l.amount).font(.system(size: 14, weight: .bold)).monospacedDigit()
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 16)
    }

    private var policyNote: some View {
        // Shipper of record = the signed-in user (live session) — never a
        // hardcoded party.
        let holderName = session.user?.name ?? "—"
        let holderInitials: String = {
            guard let n = session.user?.name, !n.isEmpty else { return "—" }
            let parts = n.split(separator: " ").prefix(2)
            let joined = parts.compactMap { $0.first }.map(String.init).joined().uppercased()
            return joined.isEmpty ? "—" : joined
        }()
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(eusoDiagonal).frame(width: 20, height: 20)
                Text(holderInitials).font(.system(size: 9, weight: .bold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Shipper of record · \(holderName)").font(.system(size: 12, weight: .semibold))
                Text(vm.isBound ? "coverage bound"
                     : (vm.hasQuote ? "quote ready" : "no policy on file"))
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(ink.sub)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(ink.note))
    }

    private var ctaRow: some View {
        // Two honest stages: quote first (re-prices the user's own declared
        // inputs), then bind the live quote. Never a fake "purchased" state.
        let ctaTitle = vm.hasQuote ? "Purchase cover" : (vm.isBound ? "Re-quote cover" : "Get quote")
        return HStack(spacing: 8) {
            Button { Task { await vm.purchase() } } label: {
                Group {
                    if vm.isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text(ctaTitle).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 48).background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(eusoPrimary))
            }
            .disabled(vm.isWorking)
            Button { showClause = true } label: {
                Text("Clause").font(.system(size: 15, weight: .semibold)).foregroundColor(ink.text)
                    .frame(width: 116, height: 48).background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(ink.soft).overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(ink.hair, lineWidth: 1)))
            }
        }
    }

    private var clauseSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(clauseStatusTitle)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(ink.text)
                    Text(clauseStatusSubtitle)
                        .font(.system(size: 12))
                        .foregroundColor(ink.sub)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        clauseRow("Insured value", vm.c.insuredValue)
                        Divider().overlay(ink.hair)
                        clauseRow("Premium", vm.c.premium)
                        Divider().overlay(ink.hair)
                        clauseRow("Rate", vm.c.ratePct)
                        Divider().overlay(ink.hair)
                        clauseRow("Deductible", vm.c.deductible)
                        Divider().overlay(ink.hair)
                        clauseRow("Certificate", vm.c.certStatus)
                        Divider().overlay(ink.hair)
                        clauseRow("Terms", vm.c.bindTerms)
                    }
                    .background(RoundedRectangle(cornerRadius: 16).fill(ink.card))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(ink.hair, lineWidth: 1))

                    if vm.c.lines.isEmpty {
                        Text("Get a quote from declared cargo before purchase terms can be reviewed.")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(ink.sub)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 16).fill(ink.note))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quote lines")
                                .font(.system(size: 9, weight: .heavy))
                                .kerning(1.0)
                                .foregroundColor(ink.faint)
                            ForEach(vm.c.lines) { line in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(line.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(ink.text)
                                    Spacer(minLength: 8)
                                    Text(line.amount)
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(ink.text)
                                }
                                Text(line.detail)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(ink.sub)
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(ink.card))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ink.hair, lineWidth: 1))
                    }

                    ShareLink(item: clausePacket) {
                        Text("Share clause summary")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(eusoPrimary))
                    }
                    .disabled(vm.c.insuredValue == "—" && vm.c.premium == "—")
                }
                .padding(20)
            }
            .background(ink.page.ignoresSafeArea())
            .navigationTitle("Clause")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showClause = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func clauseRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ink.sub)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(ink.text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var clauseStatusTitle: String {
        if vm.isBound { return "Bound cargo clause" }
        if vm.hasQuote { return "Quoted cargo clause" }
        return "Cargo clause pending"
    }

    private var clauseStatusSubtitle: String {
        if vm.isBound { return "These terms are generated from the active per-load policy on file." }
        if vm.hasQuote { return "These terms are generated from the live quote and bind only after purchase." }
        return "No per-load policy or quote is selected yet."
    }

    private var clausePacket: String {
        let holderName = session.user?.name ?? "Unknown holder"
        let lineText = vm.c.lines.map { "- \($0.title): \($0.amount) · \($0.detail)" }.joined(separator: "\n")
        return """
        EusoTrip Cargo Insurance Clause Summary
        Holder: \(holderName)
        Status: \(clauseStatusTitle)
        Insured value: \(vm.c.insuredValue)
        Premium: \(vm.c.premium)
        Rate: \(vm.c.ratePct)
        Deductible: \(vm.c.deductible)
        Certificate: \(vm.c.certStatus)
        Terms: \(vm.c.bindTerms)

        Quote lines:
        \(lineText.isEmpty ? "No quote lines on file." : lineText)
        """
    }
}

struct IridescentHairline_606: View {
    let scheme: ColorScheme
    var body: some View {
        LinearGradient(colors: [Color(red: 0.078, green: 0.451, blue: 1.0).opacity(scheme == .dark ? 0.40 : 0.55), Color(red: 0.745, green: 0.004, blue: 1.0).opacity(scheme == .dark ? 0.40 : 0.55)], startPoint: .leading, endPoint: .trailing)
            .frame(height: 1).frame(maxWidth: .infinity)
    }
}

#Preview("606 · Rail Cargo Insurance · Night") { RailCargoInsuranceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("606 · Rail Cargo Insurance · Day")   { RailCargoInsuranceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
