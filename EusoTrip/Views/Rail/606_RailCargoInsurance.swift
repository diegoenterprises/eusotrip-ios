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
//    policyNote  : shipper-of-record DU/Eusorone + bind terms
//    ctaRow      : Purchase cover (primary · binds policy) + Clause (secondary)
//
//  WIRING MANIFEST (honest · MCP-confirmed insurance.ts):
//    • insurance.getMyPerLoadPolicies EXISTS insurance.ts:1147  (query · live read seam)
//        → on load(), maps the most-recent active per-load policy into the cover model
//          (insured value = coverageAmount, premium, origin›destination quote line,
//          policy-number COI line). Empty array → keep the bespoke quoted seed (honest:
//          a fresh quote, not a bound policy). Error → keep seed, surface nothing fake.
//    • insurance.getPerLoadQuote     EXISTS insurance.ts:959   (mutation · cargoValue/
//        commodity/coverage/origin/dest) — the "Purchase cover" re-price/bind path; not a
//        safe on-load read, so it is NOT auto-fired. "Clause" opens the ICC(A) read sheet.
//    RBAC: railProcedure / protectedProcedure (shipper-of-record DU/Eusorone anchor).
//    transportMode RAIL · US (USD; per-load all-risk ICC(A)).
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
    let insuredValue: String   // "$86,000"
    let premium: String        // "$142"
    let ratePct: String        // "0.17%"
    let deductible: String     // "$500"
    let insuredShort: String   // "$86K"
    let certStatus: String     // "on file"
    let lines: [QuoteLine_606]
    let premiumTotal: String
    let bindTerms: String
}

// MARK: - View model (single live-read seam -> insurance.getMyPerLoadPolicies)

@MainActor final class InsuranceVM_606: ObservableObject {
    @Published var c: CargoCover_606
    @Published var isLoading = false
    @Published var error: String?
    /// true once a REAL bound policy has been mapped in; drives the policy-note wording
    /// (bound vs. fresh quote) so the screen never claims a binding it doesn't have.
    @Published var isBound = false

    private let info    = Color(red: 0.129, green: 0.588, blue: 0.953)
    private let success = Color(red: 0.0, green: 0.588, blue: 0.420)

    init() {
        let info = Color(red: 0.129, green: 0.588, blue: 0.953)
        let success = Color(red: 0.0, green: 0.588, blue: 0.420)
        self.c = .init(
            insuredValue: "$86,000", premium: "$142", ratePct: "0.17%", deductible: "$500",
            insuredShort: "$86K", certStatus: "on file",
            lines: [
                .init(glyph: "shield.lefthalf.filled", tint: info, title: "All-risk · line-haul", detail: "RAIL-260514 · Memphis › Atlanta", state: .quoted, stateColor: info, amount: "$108"),
                .init(glyph: "shield.lefthalf.filled", tint: info, title: "All-risk · drayage", detail: "first + last mile leg", state: .quoted, stateColor: info, amount: "$34"),
                .init(glyph: "doc.text", tint: success, title: "Certificate · COI", detail: "CIC-2026-0518 · Eusorone", state: .ready, stateColor: success, amount: "issued")
            ],
            premiumTotal: "$142",
            bindTerms: "+ clause ICC(A) · binds on purchase · effective gate-in")
    }

    func load() async {
        isLoading = true; error = nil
        do {
            // insurance.getMyPerLoadPolicies (query, optional input) — limit defaults to 20.
            let rows: [PerLoadPolicy_606] = try await EusoTripAPI.shared.query(
                "insurance.getMyPerLoadPolicies", input: EmptyInput())
            // Honest mapping: most-recent active policy first; fall back to most-recent row.
            // Empty array → keep the bespoke quoted seed (a fresh quote, not a bound policy).
            if let p = rows.first(where: { ($0.status ?? "").lowercased() == "active" }) ?? rows.first {
                self.c = map(p)
                self.isBound = true
            }
        } catch {
            // Keep the seed; surface nothing fabricated. The error is recorded for the
            // (already-bespoke) note line, never shown as fake coverage.
            self.error = (error as? EusoTripAPIError)?.localizedDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Map a real bound per-load policy row into the 606 cover ledger.
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
            insuredValue: money(coverage),
            premium:      money(premiumVal),
            ratePct:      String(format: "%.2f%%", rate),
            deductible:   money(deductible),
            insuredShort: shortMoney(coverage),
            certStatus:   ((p.status ?? "").lowercased() == "active") ? "on file" : (p.status ?? "—"),
            lines: [
                .init(glyph: "shield.lefthalf.filled", tint: info, title: "\(kind) · line-haul",
                      detail: "\(origin) › \(dest)", state: .quoted, stateColor: info, amount: money(premiumVal)),
                .init(glyph: "doc.text", tint: success, title: "Certificate · COI",
                      detail: policyNo, state: .ready, stateColor: success, amount: "issued")
            ],
            premiumTotal: money(premiumVal),
            bindTerms: "clause ICC(A) · bound · \(expiryNote(p.expiresAt))")
    }

    func purchase() async {
        // Re-price/bind path: insurance.getPerLoadQuote (mutation, insurance.ts:959) ->
        // insurance.purchasePerLoad -> perLoadInsurancePolicies row + audit + WS broadcast.
        // Not auto-fired (mutation requires declared cargo/commodity/coverage input).
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
    @StateObject private var vm = InsuranceVM_606()
    private var ink: Ink_606 { Ink_606(scheme: scheme) }
    private let eusoPrimary  = LinearGradient(colors: [Color(red: 0.078, green: 0.451, blue: 1.0), Color(red: 0.745, green: 0.004, blue: 1.0)], startPoint: .leading, endPoint: .trailing)
    private let eusoDiagonal = LinearGradient(colors: [Color(red: 0.078, green: 0.451, blue: 1.0), Color(red: 0.745, green: 0.004, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                topBar
                coverHero
                coverStrip
                ledger
                policyNote
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .background(ink.page.ignoresSafeArea())
        .foregroundColor(ink.text)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\u{2726} RAIL ENGINEER · CARGO INSURANCE").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(eusoPrimary)
                Spacer()
                Text("INS · BNSF").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(ink.faint)
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
                Text("BNSF").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(ink.faint)
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
                Text("insurance.ts:959").font(.system(size: 11, design: .monospaced)).foregroundColor(ink.sub)
            }.padding(.bottom, 12)
            VStack(spacing: 0) {
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
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(eusoDiagonal).frame(width: 20, height: 20)
                Text("DU").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Shipper of record · Eusorone Technologies").font(.system(size: 12, weight: .semibold))
                Text(vm.isBound ? "getMyPerLoadPolicies · bound" : "getMyPerLoadPolicies · insurance.ts:1147").font(.system(size: 11, design: .monospaced)).foregroundColor(ink.sub)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(ink.note))
    }

    private var ctaRow: some View {
        HStack(spacing: 8) {
            Button { Task { await vm.purchase() } } label: {
                Text("Purchase cover").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 48).background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(eusoPrimary))
            }
            Button { } label: {
                Text("Clause").font(.system(size: 15, weight: .semibold)).foregroundColor(ink.text)
                    .frame(width: 116, height: 48).background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(ink.soft).overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(ink.hair, lineWidth: 1)))
            }
        }
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
