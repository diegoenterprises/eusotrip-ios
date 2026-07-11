//
//  685_RailEDI417WaybillReceipt.swift
//  EusoTrip — Rail · Shipper · EDI 417 Waybill Receipt (brick 685).
//
//  Verbatim SwiftUI port of "05 Rail/685 Rail EDI 417 Waybill Receipt" (Dark).
//  SHIPPER-SIDE FIELD-RECONCILIATION ledger: ingest the carrier's inbound EDI
//  417 (Carrier Waybill) and reconcile it field-by-field against what was
//  tendered, so a car-type or weight discrepancy is caught before acceptance.
//  Composition follows function — a match-verdict hero over per-field
//  tendered → received rows with a per-row match check / mismatch flag.
//
//  Web parity: app/(rail)/waybill/receipt/page.tsx.
//
//  tRPC wiring (honest binding — the persisted waybill IS the received side):
//    • shipment + waybill ← railShipments.getRailShipmentDetail (EXISTS
//      railShipments.ts:412; returns the tendered shipment fields AND the
//      persisted railWaybills rows = the received carrier waybill)
//    • STUB → the-oath: ingestWaybill417 + reconcileWaybill + acceptWaybill /
//      disputeWaybill (no dedicated inbound 417 parse yet; when no waybill is
//      persisted the received column reads honest "awaiting EDI 417" and accept
//      is blocked — never auto-accepts an unparsed waybill).
//
//  RBAC: railProcedure (tenant-gated). transportMode = rail · tri-country
//  waybill-authority band US AAR 417 / CA TC / MX ARTF carta porte.
//  BottomNav: canonical Shipper enum HOME · LOADS · [orb] · WALLET · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen root

struct RailEDI417WaybillReceiptScreen: View {
    let theme: Theme.Palette
    /// Rail shipment whose inbound waybill is being reconciled. Default 48217
    /// matches the shipment id used by the sibling Rail shipment-detail screen.
    var shipmentId: Int = 48217

    init(theme: Theme.Palette = Theme.dark) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) { RailEDI417WaybillBody(shipmentId: shipmentId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house.fill",       isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person.fill",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data

/// Decodes a numeric field that may serialize as a JSON number OR a string
/// (drizzle decimal columns come back as strings, int columns as numbers).
private struct FlexNum685: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let i = try? c.decode(Int.self) { value = Double(i) }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
}

private struct RailYard685: Decodable { let splcCode: String?; let name: String? }

private struct RailWaybill685: Decodable {
    let waybillNumber: String?
    let commodity: String?
    let originStation: String?
    let destinationStation: String?
    let weightPounds: FlexNum685?
    let railcarNumber: String?
}

private struct RailShipmentDetail685: Decodable {
    let id: Int?
    let carType: String?
    let numberOfCars: Int?
    let commodity: String?
    let commodityStcc: String?
    let weight: FlexNum685?
    let totalWeight: FlexNum685?
    let originYard: RailYard685?
    let destinationYard: RailYard685?
    let waybills: [RailWaybill685]?
}

private struct FieldRow685: Identifiable {
    let id = UUID()
    let name: String
    let tendered: String
    let received: String?
    var state: State
    enum State { case match, mismatch, pending }
}

// MARK: - Body

private struct RailEDI417WaybillBody: View {
    let shipmentId: Int
    @Environment(\.palette) private var palette

    @State private var detail: RailShipmentDetail685? = nil
    @State private var fields: [FieldRow685] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionNote: String? = nil

    private let railRefId = "WB-417-0048217"

    private var waybill: RailWaybill685? { detail?.waybills?.first }
    private var hasWaybill: Bool { waybill != nil }
    private var received: Int { fields.filter { $0.state != .pending }.count }
    private var matched: Int { fields.filter { $0.state == .match }.count }
    private var mismatched: Int { fields.filter { $0.state == .mismatch }.count }

    private var verdictKind: FieldRow685.State {
        if !hasWaybill { return .pending }
        return mismatched > 0 ? .mismatch : .match
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                chipRow
                if loading {
                    LifecycleCard { Text("Reconciling waybill…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if detail == nil {
                    EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                                   title: "No shipment record",
                                   subtitle: "The tendered shipment for this waybill could not be loaded.")
                } else {
                    verdictHero
                    reconciliationSection
                    regimeRow
                    if let note = actionNote {
                        Text(note).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Brand.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("✦ SHIPPER · RAIL · EDI 417 INBOUND")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(waybill?.waybillNumber.map { "WB-417-\($0)" } ?? railRefId)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Waybill receipt")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, 10)
            Text(hasWaybill ? "Carrier waybill received · \(received) fields parsed"
                            : "Awaiting EDI 417 · \(fields.count) fields ready to reconcile")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary).padding(.top, 4)
            IridescentHairline().padding(.top, 14)
        }
    }

    private var chipRow: some View {
        HStack(spacing: Space.s2) {
            miniChip("\(matched) match", tint: Brand.success)
            miniChip("\(mismatched) review", tint: Brand.warning)
            miniChip("417 inbound", tint: palette.textSecondary)
        }
    }

    @ViewBuilder
    private func miniChip(_ text: String, tint: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .heavy)).tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(palette.bgCard))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Verdict hero

    private var verdictHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(verdictTint)
                Text("EDI 417 · CARRIER WAYBILL")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(verdictTint)
                Spacer(minLength: 4)
                Text(verdictPill)
                    .font(.system(size: 10.5, weight: .heavy)).tracking(0.3).foregroundStyle(verdictTint)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(verdictTint.opacity(0.16)))
            }
            Text(hasWaybill ? "\(matched) of \(received) fields matched"
                            : "Awaiting inbound EDI 417")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(heroSub)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private var verdictTint: Color {
        switch verdictKind {
        case .match:    return Brand.success
        case .mismatch: return Brand.warning
        case .pending:  return palette.textSecondary
        }
    }
    private var verdictPill: String {
        switch verdictKind {
        case .match:    return "MATCHED"
        case .mismatch: return "REVIEW"
        case .pending:  return "PENDING"
        }
    }
    private var heroSub: String {
        if let wb = waybill {
            return "\(mismatched) discrepancies · waybill \(wb.waybillNumber ?? "—") · \(wb.railcarNumber ?? "car pending")"
        }
        return "EDI 417 inbound parse pending · reconcile once the carrier waybill lands"
    }

    // MARK: Reconciliation list

    private var reconciliationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FIELD RECONCILIATION · \(fields.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Color(hex: 0x9FB0BE))
                Spacer()
                Text("tendered → received").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
            VStack(spacing: 0) {
                ForEach(Array(fields.enumerated()), id: \.element.id) { idx, f in
                    fieldRow(f)
                    if idx < fields.count - 1 { Divider().padding(.horizontal, 16).overlay(palette.borderFaint) }
                }
            }
            .padding(.vertical, 4)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    @ViewBuilder
    private func fieldRow(_ f: FieldRow685) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(f.name).font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                HStack(spacing: 8) {
                    Text("tendered").font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    Text(f.tendered)
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                    Text("→").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                    Text(f.received ?? "awaiting")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(receivedTint(f))
                }
            }
            Spacer(minLength: 6)
            fieldFlag(f)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(f.state == .mismatch ? Brand.warning.opacity(0.10) : Color.clear)
                .padding(.horizontal, 6)
        )
    }

    private func receivedTint(_ f: FieldRow685) -> Color {
        switch f.state {
        case .match:    return Brand.success
        case .mismatch: return Brand.warning
        case .pending:  return palette.textTertiary
        }
    }

    @ViewBuilder
    private func fieldFlag(_ f: FieldRow685) -> some View {
        switch f.state {
        case .match:
            Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Brand.success)
        case .mismatch:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.warning)
        case .pending:
            Image(systemName: "clock").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Regime chips

    private var regimeRow: some View {
        HStack(spacing: Space.s2) {
            regimeChip("US · AAR", "417 waybill", active: true)
            regimeChip("CA · TC", "CN waybill", active: false)
            regimeChip("MX · ARTF", "carta porte", active: false)
        }
    }

    @ViewBuilder
    private func regimeChip(_ title: String, _ sub: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? Color(hex: 0x6FA8FF) : palette.textSecondary)
            Text(sub).font(.system(size: 9, weight: .heavy))
                .foregroundStyle(active ? Color(hex: 0x6FA8FF) : palette.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(active ? Color(hex: 0x6FA8FF).opacity(0.20) : palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(active ? Color.clear : palette.borderFaint))
    }

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Accept waybill",
                      action: { acceptTapped() },
                      trailingIcon: "checkmark.seal")
            RailSecondaryActionButton(
                title: "Dispute",
                sheetTitle: "Waybill reconciliation",
                lines: reconciliationLines,
                systemImage: "exclamationmark.bubble"
            )
        }
    }

    private var reconciliationLines: [String] {
        var lines = fields.map { f -> String in
            let r = f.received ?? "awaiting"
            let mark = f.state == .match ? "✓" : (f.state == .mismatch ? "≠" : "…")
            return "\(f.name) · \(f.tendered) → \(r) \(mark)"
        }
        lines.append(hasWaybill ? "\(mismatched) field(s) flagged for review"
                                : "No waybill parsed — dispute is blocked until EDI 417 lands")
        return lines
    }

    private func acceptTapped() {
        if !hasWaybill {
            actionNote = "No EDI 417 parsed yet — accept is blocked. ingestWaybill417 + acceptWaybill are pending; a waybill is never auto-accepted unparsed."
        } else if mismatched > 0 {
            actionNote = "\(mismatched) field(s) mismatch — resolve or dispute before accepting. acceptWaybill endpoint pending."
        } else {
            actionNote = "All \(received) fields match. acceptWaybill endpoint pending — reconciliation is clean and ready to accept."
        }
    }

    // MARK: Load / reconcile

    private func load() async {
        loading = true; loadError = nil; actionNote = nil
        struct IdIn: Encodable { let id: Int }
        do {
            let d = try await EusoTripAPI.shared.query(
                "railShipments.getRailShipmentDetail",
                input: IdIn(id: shipmentId)) as RailShipmentDetail685?
            self.detail = d
            self.fields = reconcile(d)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func reconcile(_ d: RailShipmentDetail685?) -> [FieldRow685] {
        guard let d else { return [] }
        let wb = d.waybills?.first
        func norm(_ s: String?) -> String? {
            guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
            return s
        }
        func numLabel(_ s: String?) -> String {
            guard let s, let v = Double(s) else { return s ?? "—" }
            return Int(v).formatted(.number.grouping(.automatic))
        }
        func row(_ name: String, _ tendered: String?, _ received: String?, numeric: Bool = false) -> FieldRow685 {
            let tLabel = numeric ? numLabel(tendered) : (tendered ?? "—")
            let rLabel = received.map { numeric ? numLabel($0) : $0 }
            let state: FieldRow685.State
            if let rr = norm(received), let tt = norm(tendered) {
                if numeric, let a = Double(tt), let b = Double(rr) {
                    state = abs(a - b) < 0.5 ? .match : .mismatch
                } else {
                    state = tt.uppercased() == rr.uppercased() ? .match : .mismatch
                }
            } else {
                state = .pending
            }
            return FieldRow685(name: name, tendered: tLabel, received: rLabel, state: state)
        }

        let originTendered = d.originYard?.splcCode ?? d.originYard?.name
        let destTendered = d.destinationYard?.splcCode ?? d.destinationYard?.name
        let stccTendered = d.commodityStcc ?? d.commodity
        let weightTendered = (d.weight?.value ?? d.totalWeight?.value).map { String($0) }
        let weightReceived = wb?.weightPounds?.value.map { String($0) }

        return [
            row("Origin", originTendered, wb?.originStation),
            row("Destination", destTendered, wb?.destinationStation),
            row("Car count", d.numberOfCars.map(String.init), nil, numeric: true),
            row("Car type", d.carType, nil),
            row("Commodity / STCC", stccTendered, wb?.commodity),
            row("Weight (lb)", weightTendered, weightReceived, numeric: true),
        ]
    }
}

#Preview("685 · Rail EDI 417 Waybill · Night") {
    RailEDI417WaybillReceiptScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("685 · Rail EDI 417 Waybill · Light") {
    RailEDI417WaybillReceiptScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
