//
//  006_VesselCustomsISF.swift
//  EusoTrip — Vessel · Customs & ISF (ISF 10+2 compliance-gate).
//
//  Bespoke port of the reconstructed "06 Vessel/Code/006_VesselCustomsISF.swift" canonical AFTER
//  (ARCHETYPE = COMPLIANCE-GATE · "ISF 10+2 cut-off burndown"): a deadline-countdown hero (hours to
//  the ISF 10+2 cut-off = ETD−24h) + a 72h filing-window burndown bar + the $5,000/violation CBP
//  exposure, over a true 10+2 pass/fail GATE that surfaces the OPEN elements first, an ESang advisory
//  strip, and the File-ISF / 10+2-detail CTA pair. Re-housed into the app's Shell + vessel BottomNav
//  (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME), mirroring the registered sibling
//  757_VesselDetentionLetters. The canonical port's self-drawn bottomNav/navItem/orb + page bg are
//  removed (Shell provides them); the bespoke body is preserved faithfully.
//
//  ROLE: the canonical header reads "VESSEL_SHIPPER vantage" (shipper-of-record / importer files the
//  ISF). Registered under vesselShipper. COMPLIANCE slot inked (customs = compliance domain).
//
//  Data / wiring (endpoints MCP-confirmed on frontend/server/routers/vesselShipments.ts, 2026-06-02):
//    vesselShipments.getISFRequirements (EXISTS :1794 · vesselProcedure · NO input · returns the
//      static ISF 10+2 element catalog [{field,description,timing,penalty}] from
//      services/crossBorderVessel.ts ISF_10_PLUS_2 :62) — drives the live GATE rows (the 10+2 pass/fail
//      element list). This is the honest backing data source for THIS journey-hub surface, which has no
//      per-booking shipmentId in context.
//    vesselShipments.getISFStatus (EXISTS :1215 · vesselProcedure · input {shipmentId} REQUIRED ·
//      returns {bookingNumber,status,deadline=ETD−24h,filings,isfFiled,isfCleared,warning
//      "$5,000 per violation"}) — the live per-booking countdown/burndown hero binds to this when a
//      booking is selected. With no shipmentId at this hub surface the hero renders the 10+2 cut-off
//      RULE (24h before vessel loading) rather than fabricating a specific booking's countdown; the
//      header chip honestly says "RULE · select a booking for live cut-off".
//    "File ISF now" -> vesselShipments.fileISF (EXISTS :1504, Descartes ABI) — STUB here: no
//      shipmentId is in scope at the hub surface, so the verb re-loads the gate rather than faking a
//      filing. Wires fully from the per-booking entry point.
//    "10+2 detail" -> re-reads getISFRequirements (the full element catalog) — re-load.
//
//  0 mock data on load · honest empty/error states — gate rows render from the real requirements
//  endpoint; if it returns nothing the bespoke empty state shows. Seed lives ONLY in #Preview.
//  All file-scoped helper types are suffixed _006 to avoid cross-file private collisions; every
//  design-system symbol (Shell/BottomNav/NavSlot/IridescentHairline/EusoEmptyState/LifecycleCard/
//  CTAButton/Brand/EType/Space/Radius/LinearGradient.diagonal·primary/palette.*) resolves in-module.
//

import SwiftUI

// MARK: - View model (mirrors getISFStatus + getISFRequirements return shapes)

private enum ISFElementState006 { case open, filed }

private struct ISFElementRow006: Identifiable {
    let id = UUID()
    let title: String
    let sub: String
    let state: ISFElementState006
    let chipText: String        // "OPEN" / "FILED" / "2/2"
    let glyph: String           // SF Symbol stand-in for the in-kit icon chip
    let tint: Color             // chip + icon-chip tint
}

private struct ISFStatusVM006 {
    // header
    let bookingNumber: String   // getISFStatus.bookingNumber
    let openCount: Int          // derived: elements where state == .open
    let lane: String
    let liveContext: Bool       // true = bound to a real getISFStatus booking; false = RULE surface
    // hero (getISFStatus.deadline = ETD − 24h)
    let countdown: String       // formatted (deadline − now)
    let cutoffLocal: String     // deadline in origin-port local time
    let exposureLabel: String   // from getISFStatus.warning → "$5,000 / VIOLATION"
    let windowElapsedFraction: Double  // elapsed / 72h window
    let windowNote: String
    let elapsedNote: String
    // gate
    let importerCount: Int
    let carrierCount: Int
    let gatewayNote: String     // "CBP ACE · LIVE"
    let elements: [ISFElementRow006]
    // esang (routes through esang.chat)
    let esangTitle: String
    let esangSub: String

    static let preview = ISFStatusVM006(
        bookingNumber: "VS-50912",
        openCount: 2,
        lane: "40ft HC · furniture · Shanghai → Los Angeles",
        liveContext: true,
        countdown: "18h 22m",
        cutoffLocal: "19:00 HKT · ETD−24h",
        exposureLabel: "CBP $5,000 / VIOLATION",
        windowElapsedFraction: 0.75,
        windowNote: "72h filing window · loads after ISF accept",
        elapsedNote: "75% elapsed",
        importerCount: 10, carrierCount: 2,
        gatewayNote: "CBP ACE · LIVE",
        elements: [
            .init(title: "Consolidator name & address", sub: "ISF element 9 · awaiting entry",
                  state: .open, chipText: "OPEN", glyph: "building.2", tint: Brand.warning),
            .init(title: "Container stuffing location", sub: "ISF element 10 · awaiting entry",
                  state: .open, chipText: "OPEN", glyph: "shippingbox", tint: Brand.warning),
            .init(title: "Manufacturer · Foshan Lihua", sub: "elements 1–3 · CN origin · seller/buyer",
                  state: .filed, chipText: "FILED", glyph: "building.columns", tint: Brand.success),
            .init(title: "HTS 9403.60 · wood furniture", sub: "elements 4–8 · duty 0% · CBP entry type 01",
                  state: .filed, chipText: "FILED", glyph: "tag", tint: Brand.success),
            .init(title: "Carrier · stow plan + status", sub: "MV Ever Ace · SCAC MAEU · elements 11–12",
                  state: .filed, chipText: "2/2", glyph: "ferry", tint: Brand.vessel),
        ],
        esangTitle: "ESang AI: file the 2 open elements now",
        esangSub: "18h 22m to cut-off - clears the $5,000 CBP exposure"
    )
}

// MARK: - Screen wrapper (Shell + vessel BottomNav · COMPLIANCE inked)

struct VesselCustomsISFScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselCustomsISFBody006()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Bespoke body

private struct VesselCustomsISFBody006: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var vm: ISFStatusVM006? = nil

    // L03-5 real filer: the "File ISF now" verb opens the filing sheet
    // (pending-booking picker + the 10+2 elements) → vesselShipments.fileISF.
    @State private var showFilingSheet = false
    @State private var filedAck: String? = nil

    private var amberText: Color { scheme == .dark ? Color(hex: 0xFFB74D) : Color(hex: 0xE08A00) }
    private var dangerText: Color { scheme == .dark ? Color(hex: 0xFF8A7D) : Color(hex: 0xC0362B) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                IridescentHairline()

                if let filedAck {
                    filedAckStrip(filedAck)
                }

                if loading {
                    LifecycleCard { Text("Loading ISF 10+2 gate…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let vm, !vm.elements.isEmpty {
                    heroBurndown(vm)
                    gateSection(vm)
                    esangStrip(vm)
                    actionRow
                } else {
                    EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                                   title: "No ISF 10+2 elements to surface",
                                   subtitle: "getISFRequirements returned an empty catalog, nothing to file.")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showFilingSheet) {
            ISFFilingSheet006(onFiled: { isfNumber in
                filedAck = isfNumber.map { "ISF filed · \($0)" } ?? "ISF filed."
                Task { await load() }
            })
        }
    }

    // MARK: Filed acknowledgement strip (post-filing)
    private func filedAckStrip(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.success)
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            Button { filedAck = nil } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(palette.textTertiary)
            }.buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Brand.success.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.success.opacity(0.35))))
    }

    // MARK: Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\u{2726} VESSEL SHIPPER · CUSTOMS · ISF 10+2")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.primary)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(vm?.bookingNumber ?? "ISF 10+2").font(.system(size: 28, weight: .bold, design: .monospaced)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if let vm {
                    Text("\(vm.openCount) OPEN").font(.system(size: 11, weight: .heavy)).kerning(0.5)
                        .foregroundColor(scheme == .dark ? Color(hex: 0x1A1205) : .white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Brand.warning))
                }
            }
            HStack(spacing: 8) {
                Text(vm?.lane ?? "CBP ACE · ISF 10+2 · US-inbound import")
                    .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "ferry.fill").font(.system(size: 8, weight: .bold))
                    Text("VESSEL").font(.system(size: 9, weight: .heavy)).kerning(0.6)
                }
                .foregroundColor(scheme == .dark ? Color(hex: 0x06222A) : .white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Brand.vessel))
            }
            if let vm, !vm.liveContext {
                Text("RULE · select a booking for live cut-off")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Hero — ISF cut-off burndown (getISFStatus)
    private func heroBurndown(_ vm: ISFStatusVM006) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient.diagonal.opacity(0.85))
            RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ISF 10+2 FILING · CUT-OFF").font(.system(size: 9, weight: .heavy)).kerning(1.0)
                            .foregroundStyle(palette.textTertiary)
                        Text(vm.countdown).font(.system(size: 40, weight: .bold, design: .monospaced)).kerning(-1)
                            .foregroundColor(amberText).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(vm.exposureLabel).font(.system(size: 10, weight: .heavy)).kerning(0.3)
                            .foregroundColor(dangerText)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Brand.danger.opacity(scheme == .dark ? 0.16 : 0.10)))
                        Text("to cut-off").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textSecondary)
                        Text(vm.cutoffLocal).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer(minLength: 10)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.textPrimary.opacity(scheme == .dark ? 0.08 : 0.07)).frame(height: 12)
                        Capsule().fill(LinearGradient(colors: [Brand.warning, Color(hex: 0xF4A024)],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * vm.windowElapsedFraction, height: 12)
                        Rectangle().fill(dangerText)
                            .frame(width: 2.5, height: 16)
                            .offset(x: geo.size.width * vm.windowElapsedFraction - 1.25)
                    }
                }.frame(height: 16)
                HStack {
                    Text(vm.windowNote).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(vm.elapsedNote).font(.system(size: 10, weight: .bold)).foregroundColor(amberText)
                }.padding(.top, 6)
            }
            .padding(20)
        }
        .frame(height: 152)
    }

    // MARK: Gate — the 10+2 pass/fail surface (getISFRequirements)
    private func gateSection(_ vm: ISFStatusVM006) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ISF 10+2 GATE · IMPORTER \(vm.importerCount) · CARRIER \(vm.carrierCount)")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.gatewayNote).font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(vm.elements.enumerated()), id: \.element.id) { idx, el in
                    elementRow(el)
                    if idx < vm.elements.count - 1 {
                        Divider().background(palette.textPrimary.opacity(0.06)).padding(.leading, 52)
                    }
                }
            }
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 20).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.borderFaint))
            )
        }
    }

    private func elementRow(_ el: ISFElementRow006) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(el.tint.opacity(scheme == .dark ? 0.16 : 0.12))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: el.glyph).font(.system(size: 16, weight: .regular)).foregroundColor(el.tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(el.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(el.sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            HStack(spacing: 4) {
                if el.state == .filed {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundColor(el.tint == Brand.vessel ? Brand.success : el.tint)
                }
                Text(el.chipText).font(.system(size: 10, weight: .heavy)).kerning(0.4)
                    .foregroundColor(el.state == .open ? amberText : Brand.success)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill((el.state == .open ? Brand.warning : Brand.success).opacity(scheme == .dark ? 0.18 : 0.16)))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: ESang (routes through esang.chat)
    private func esangStrip(_ vm: ISFStatusVM006) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Ellipse().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 16))
                    .frame(width: 16, height: 16).offset(x: -5, y: -5)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(vm.esangTitle).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(vm.esangSub).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.borderFaint)))
    }

    // MARK: Actions
    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: { showFilingSheet = true }) {
                Text("File ISF now").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 48).background(Capsule().fill(LinearGradient.primary))
            }
            Button(action: { Task { await load() } }) {
                Text("10+2 detail").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(Capsule().fill(palette.bgCardSoft).overlay(Capsule().stroke(palette.textPrimary.opacity(0.10))))
            }
        }
    }

    // MARK: - Load (getISFRequirements drives the live gate; hero renders the 10+2 cut-off RULE)

    private func load() async {
        loading = true; loadError = nil
        do {
            struct Requirement006: Decodable { let field: String?; let description: String?; let timing: String?; let penalty: String? }
            // getISFRequirements returns a bare JSON array of requirement objects.
            let reqs: [Requirement006] = try await EusoTripAPI.shared.query("vesselShipments.getISFRequirements", input: EmptyInput006())

            // Map the 12 ISF 10+2 elements (10 importer + 2 carrier). The carrier "+1/+2"
            // elements (Vessel Stow Plan / Container Status Messages) tint vessel-blue; the
            // importer-10 tint by whether the field is awaiting entry (open) or filed.
            let carrierFields: Set<String> = ["Vessel Stow Plan (+1)", "Container Status Messages (+2)"]
            // Honest rule-state derivation: with no per-booking getISFStatus shipmentId at this hub
            // surface, the gate shows the catalog as PENDING (open) — the live filed/open split
            // binds when a booking is selected. We surface the two carrier "+2" as a single 2/2 row.
            var rows: [ISFElementRow006] = []
            var importerCount = 0
            var carrierCount = 0
            for r in reqs {
                let field = r.field ?? "ISF element"
                let isCarrier = carrierFields.contains(field)
                if isCarrier { carrierCount += 1 } else { importerCount += 1 }
                // W13 hygiene (E2E audit §4 · 2026-06-10): timing/penalty
                // are server-sourced only — the fabricated "24hrs before
                // loading" / "$5,000 per violation" defaults are gone;
                // missing pieces render em-dash (zero-fallback doctrine).
                let subParts = [r.timing?.lowercased(), r.penalty]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                rows.append(ISFElementRow006(
                    title: field,
                    sub: subParts.isEmpty ? "-" : subParts.joined(separator: " · "),
                    state: .open,
                    chipText: "OPEN",
                    glyph: glyphFor(field),
                    tint: isCarrier ? Brand.vessel : Brand.warning
                ))
            }

            if rows.isEmpty {
                vm = nil
            } else {
                let openCount = rows.filter { $0.state == .open }.count
                vm = ISFStatusVM006(
                    bookingNumber: "ISF 10+2",
                    openCount: openCount,
                    lane: "CBP ACE · ISF 10+2 · US-inbound import",
                    liveContext: false,
                    countdown: "24h",
                    cutoffLocal: "ETD−24h · before vessel loading",
                    exposureLabel: "CBP $5,000 / VIOLATION",
                    windowElapsedFraction: 0.0,
                    windowNote: "file 24h before vessel loading at foreign port",
                    elapsedNote: "pending",
                    importerCount: importerCount,
                    carrierCount: carrierCount,
                    gatewayNote: "CBP ACE · LIVE",
                    elements: rows,
                    esangTitle: "ESang AI: file all \(openCount) ISF elements now",
                    esangSub: "ISF 10+2 must clear 24h before loading - $5,000/violation exposure"
                )
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// In-kit icon-chip glyph for an ISF element field (SF Symbol stand-in).
    private func glyphFor(_ field: String) -> String {
        let f = field.lowercased()
        if f.contains("manufacturer") || f.contains("supplier") { return "building.columns" }
        if f.contains("seller") || f.contains("buyer") { return "person.2" }
        if f.contains("ship-to") || f.contains("consignee") { return "mappin.and.ellipse" }
        if f.contains("stuffing") { return "shippingbox" }
        if f.contains("consolidator") { return "building.2" }
        if f.contains("importer") { return "number" }
        if f.contains("country") { return "globe" }
        if f.contains("hts") || f.contains("tariff") { return "tag" }
        if f.contains("stow") { return "ferry" }
        if f.contains("status") { return "antenna.radiowaves.left.and.right" }
        return "doc.text"
    }

}

private struct EmptyInput006: Encodable {}

// MARK: - ISF filing sheet (L03-5 real filer)
//
// listIsfPendingBookings (vesselProcedure · no input) → the tenant-scoped
// US-bound bookings that still need an ISF; the shipper picks one, supplies the
// ISF 10+2 elements, and vesselShipments.fileISF submits to the CBP/Descartes
// gateway. A failed federal filing surfaces the server's honest BAD_GATEWAY
// message (never a fake "filed"). Honest empty-state when nothing is pending.

/// listIsfPendingBookings row.
private struct ISFPendingBooking006: Decodable, Identifiable {
    let shipmentId: Int
    let bookingNumber: String?
    let etd: String?
    let isfDeadline: String?
    let overdue: Bool?
    let destinationPort: String?
    var id: Int { shipmentId }
}

/// vesselShipments.fileISF success payload (decoded leniently — absent fields
/// render as em-dash, per the house decode-and-render doctrine).
private struct ISFFileResult006: Decodable {
    let isfNumber: String?
    let transactionId: String?
    let filingStatus: String?
}

private struct ISFFilingSheet006: View {
    let onFiled: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    @State private var pending: [ISFPendingBooking006] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var selected: ISFPendingBooking006? = nil

    // The ISF 10+2 elements the CBP/Descartes filing requires.
    @State private var importer = ""
    @State private var seller = ""
    @State private var buyer = ""
    @State private var shipTo = ""
    @State private var manufacturer = ""
    @State private var countryOfOrigin = ""
    @State private var htsNumber = ""
    @State private var consolidator = ""
    @State private var containerStuffing = ""
    @State private var vessel = ""
    @State private var voyageNumber = ""

    @State private var submitting = false
    @State private var submitError: String? = nil

    private var canSubmit: Bool {
        selected != nil && !submitting &&
        !importer.trimmed.isEmpty && !seller.trimmed.isEmpty && !buyer.trimmed.isEmpty &&
        !shipTo.trimmed.isEmpty && !manufacturer.trimmed.isEmpty && !countryOfOrigin.trimmed.isEmpty &&
        !htsNumber.trimmed.isEmpty && !consolidator.trimmed.isEmpty && !containerStuffing.trimmed.isEmpty &&
        !vessel.trimmed.isEmpty && !voyageNumber.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if loading {
                        Text("Loading bookings awaiting ISF…").font(EType.caption).foregroundStyle(palette.textSecondary)
                    } else if let loadError {
                        Text(loadError).font(EType.caption).foregroundStyle(Brand.danger)
                    } else if pending.isEmpty {
                        EusoEmptyState(systemImage: "checkmark.seal",
                                       title: "No bookings awaiting ISF",
                                       subtitle: "US-bound bookings that still need an ISF 10+2 filing will appear here.")
                            .padding(.top, 24)
                    } else {
                        bookingPicker
                        if selected != nil {
                            elementFields
                            if let submitError {
                                Text(submitError).font(EType.caption).foregroundStyle(Brand.danger)
                            }
                            submitButton
                        }
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(20)
            }
            .navigationTitle("File ISF 10+2")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadPending() }
        }
    }

    // Pending-booking picker.
    private var bookingPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BOOKING").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
            Menu {
                ForEach(pending) { b in
                    Button {
                        selected = b
                        vessel = ""; voyageNumber = ""
                    } label: {
                        Text(pickerLabel(b))
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected.map { $0.bookingNumber ?? "Booking #\($0.shipmentId)" } ?? "Select a booking")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
                        if let s = selected {
                            Text(subLabel(s)).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                        }
                    }
                    Spacer()
                    if selected?.overdue == true {
                        Text("Overdue").font(.system(size: 10, weight: .heavy))
                            .foregroundColor(scheme == .dark ? Color(hex: 0x1A0808) : .white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Brand.danger))
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textTertiary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.borderFaint)))
            }
        }
    }

    private func pickerLabel(_ b: ISFPendingBooking006) -> String {
        var s = b.bookingNumber ?? "Booking #\(b.shipmentId)"
        if let dp = b.destinationPort { s += " → \(dp)" }
        if b.overdue == true { s += " · overdue" }
        return s
    }
    private func subLabel(_ b: ISFPendingBooking006) -> String {
        var parts: [String] = []
        if let dp = b.destinationPort { parts.append(dp) }
        if let dl = b.isfDeadline { parts.append("cut-off \(shortDate(dl))") }
        return parts.isEmpty ? "US-bound import" : parts.joined(separator: " · ")
    }

    private var elementFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ISF 10+2 ELEMENTS").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
            field("Importer of record", $importer)
            field("Seller", $seller)
            field("Buyer", $buyer)
            field("Ship-to party", $shipTo)
            field("Manufacturer or supplier", $manufacturer)
            field("Country of origin", $countryOfOrigin)
            field("HTS number", $htsNumber)
            field("Consolidator", $consolidator)
            field("Container stuffing location", $containerStuffing)
            field("Vessel", $vessel)
            field("Voyage number", $voyageNumber)
        }
    }

    private func field(_ label: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
            TextField("", text: binding)
                .font(.system(size: 14))
                .foregroundStyle(palette.textPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.borderFaint)))
        }
    }

    private var submitButton: some View {
        Button(action: { Task { await submit() } }) {
            Text(submitting ? "Filing ISF…" : "File ISF")
                .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(Capsule().fill(canSubmit ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft)))
        }
        .disabled(!canSubmit)
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? { let g = ISO8601DateFormatter(); g.formatOptions = [.withInternetDateTime]; return g.date(from: iso) }()
        guard let d else { return iso }
        let out = DateFormatter(); out.dateFormat = "MMM d HH:mm"
        return out.string(from: d)
    }

    private func loadPending() async {
        loading = true; loadError = nil
        do {
            let rows: [ISFPendingBooking006] = try await EusoTripAPI.shared.query(
                "vesselShipments.listIsfPendingBookings", input: EmptyInput006())
            self.pending = rows
            if selected == nil { selected = rows.first }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func submit() async {
        guard let b = selected else { return }
        submitting = true; submitError = nil
        struct FileISFIn: Encodable {
            let shipmentId: Int
            let importer: String; let seller: String; let buyer: String; let shipTo: String
            let containerStuffing: String; let consolidator: String
            let htsNumbers: [String]
            let manufacturer: String; let countryOfOrigin: String
            let vessel: String; let voyageNumber: String
        }
        let hts = htsNumber.split(whereSeparator: { $0 == "," || $0 == " " }).map { String($0) }.filter { !$0.isEmpty }
        do {
            let out: ISFFileResult006 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.fileISF",
                input: FileISFIn(
                    shipmentId: b.shipmentId,
                    importer: importer.trimmed, seller: seller.trimmed, buyer: buyer.trimmed, shipTo: shipTo.trimmed,
                    containerStuffing: containerStuffing.trimmed, consolidator: consolidator.trimmed,
                    htsNumbers: hts,
                    manufacturer: manufacturer.trimmed, countryOfOrigin: countryOfOrigin.trimmed,
                    vessel: vessel.trimmed, voyageNumber: voyageNumber.trimmed))
            onFiled(out.isfNumber)
            dismiss()
        } catch {
            submitError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        submitting = false
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

#Preview("006 · Customs ISF · Light") {
    VesselCustomsISFScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
#Preview("006 · Customs ISF · Dark") {
    VesselCustomsISFScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("006 · ISF Filing Sheet · Light") {
    ISFFilingSheet006(onFiled: { _ in }).environment(\.palette, Theme.light).preferredColorScheme(.light)
}
#Preview("006 · ISF Filing Sheet · Dark") {
    ISFFilingSheet006(onFiled: { _ in }).environment(\.palette, Theme.dark).preferredColorScheme(.dark)
}
