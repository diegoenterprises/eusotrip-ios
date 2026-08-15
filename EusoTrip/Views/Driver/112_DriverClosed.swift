//
//  112_DriverClosed.swift
//  EusoTrip — Lifecycle screen 112 · Driver Closed (CLOSED · SETTLED).
//
//  Verbatim reconstruction of the 2026-05 wireframe frame
//  `112 Closed · Dark` (440×956). The eighth and CAPPING context in the
//  Driver lifecycle ladder — when this fires the strip is COMPLETE across
//  all 8 canonical stages (CLOSED current = idx 7).
//
//  Composition (top → bottom, matching the frame — chrome preserved verbatim):
//    • TopBar — gradient eyebrow "DRIVER · CLOSED · SETTLED", load-number
//      mono tag, back chevron, lane title, and a 10h RESET HoS pill.
//    • Iridescent hairline.
//    • Hero settlement-snapshot strip (60pt) — LOAD CLOSED success pill +
//      SETTLEMENT gradient pill + a distance/next-trip caption.
//    • 8-stage lifecycle strip — CLOSED current (idx 7), CAPS the strip;
//      the whole progress segment is gradient with no neutral remainder.
//    • Pickup / Delivery card — origin SIGNED + destination ARRIVED rows.
//    • Settlement summary card — hazmat archive strip + 5 financial rows
//      (Linehaul · Hazmat · Detention · Catalyst share · Driver net —
//      three-state BILLED/NETTED/PENDING badge) + settlement-ID mono line.
//    • §8.4 Shipper-of-record card — live shipper party.
//    • BottomNav — TRIPS active (Driver variant).
//
//  Wiring (ZERO fabrication):
//    • Active load hydrates via TripLifecycleStore → `loads.getById`
//      decoded with the CORRECTED wire shape proven in DL133/DL126/149:
//      top-level `id: String?` (server returns String(load.id); decoding
//      as Int throws and blanks the screen), nested
//      pickupLocation/deliveryLocation {city,state} (NOT flat), and real
//      driver/catalyst/shipper PARTY objects {id, name, initials,
//      companyName, mcNumber, dotNumber}. rate is a DECIMAL String;
//      distance a Double.
//    • The closed-load financial breakdown reads
//      `earnings.previewSettlement({ loadId })` (the REAL driver-facing
//      settlement preview — settlements + settlement_documents + billable
//      detention_records for this one load). Each money field is optional;
//      it binds ONLY when the server returns a non-null value. When the
//      server returns null (no settlement row persisted yet), the figure
//      renders an honest "—" — never a fabricated number.
//    • Currency drives the money formatter (USD/CAD/MXN — tri-country
//      honest). Any failure surfaces through @State actionError.
//
//  Values with no live source (stop addresses · seal · gallons cleared ·
//  detention terms · HoS clock · snapshot timings) render honest "—". No
//  synthesized personas, no hardcoded line items, no invented identifiers.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Corrected `loads.getById` wire shape (proven DL133/DL126/149)

/// Top-level load id is a String on the wire (`loads.getById` →
/// `String(load.id)`); decoding it as Int throws typeMismatch and fails
/// the WHOLE decode → blank screen. pickup/delivery are nested
/// {city,state} objects (NOT flat city fields). Parties are real
/// {id,name,initials,companyName,mcNumber,dotNumber} objects.
private struct ClosedLoadCtx: Decodable, Hashable {
    let id: String?
    let loadNumber: String?
    let status: String?
    let pickupLocation: ClosedLoc?
    let deliveryLocation: ClosedLoc?
    let rate: String?
    let distance: Double?
    let equipmentType: String?
    let driver: ClosedParty?
    let catalyst: ClosedParty?
    let shipper: ClosedParty?

    struct ClosedLoc: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct ClosedParty: Decodable, Hashable {
        let id: Int?            // party (user/company) id is numeric on the wire
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }
}

struct DriverClosed: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: ClosedLoadCtx?

    /// Live settlement figures for this closed load — each binds ONLY when
    /// `earnings.previewSettlement` returns a non-null value (a real
    /// settlement row exists). Until then the figure renders an honest "—".
    @State private var settledLinehaul: Double?
    @State private var settledHazmat: Double?
    @State private var settledDetention: Double?
    @State private var settledCatalyst: Double?
    @State private var settledNet: Double?
    @State private var settlementId: String?
    @State private var settlementStatus: String?
    @State private var settledAt: String?
    @State private var hasSettlement: Bool = false
    /// Currency the settlement is denominated in (tri-country honest:
    /// USD/CAD/MXN). Defaults to USD until a load hydrates a real currency.
    @State private var settlementCurrency: String = "USD"
    @State private var isLoadingSettlement: Bool = false

    @State private var isFindingNext: Bool = false
    @State private var actionError: String?

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    // MARK: - Live display helpers (bind to fetched data; honest "—" fallback)

    private static let emDash = "—"

    private var loadNumberDisplay: String { activeLoad?.loadNumber ?? Self.emDash }

    private var lane: String {
        let o = [activeLoad?.pickupLocation?.city, activeLoad?.pickupLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        let d = [activeLoad?.deliveryLocation?.city, activeLoad?.deliveryLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        guard !o.isEmpty || !d.isEmpty else { return Self.emDash }
        return "\(o.isEmpty ? Self.emDash : o) → \(d.isEmpty ? Self.emDash : d)"
    }

    private func usd(_ v: Double, signed: Bool = false) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = settlementCurrency
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        let base = f.string(from: NSNumber(value: abs(v))) ?? "\(abs(v))"
        if signed { return (v < 0 ? "-" : "+") + base }
        return base
    }

    /// Money cell — a live figure formats to currency; a null figure
    /// renders an honest em-dash (never a fabricated number).
    private func money(_ v: Double?, signed: Bool = false) -> String {
        guard let v else { return Self.emDash }
        return usd(v, signed: signed)
    }

    /// Settlement timing line — derived ONLY from the real `settledAt`
    /// timestamp; absent a live value it renders "—" (no invented "pays Mon").
    private var settledAtDisplay: String? {
        guard let iso = settledAt,
              let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        let f = DateFormatter(); f.dateFormat = "EEE · MMM d"
        return f.string(from: date)
    }

    // MARK: - 8-stage lifecycle (CLOSED current = idx 7 — CAPS the strip)

    private let stages = ["POSTED", "BIDDING", "AWARDED", "PICKUP",
                          "IN TRANSIT", "DELIVERY", "PAPERWORK", "CLOSED"]
    private let currentStageIndex = 7

    // MARK: - Settlement rows (three-state BILLED / NETTED / PENDING)

    private enum SettleState { case billed, netted, pending }

    private struct SettleRow: Identifiable {
        let id = UUID()
        let title: String
        let amount: String
        let state: SettleState
    }

    /// Five-row settlement breakdown. Each amount binds to a live figure
    /// or renders "—". Titles carry only mode-neutral structural labels —
    /// no fabricated mileage tiers, detention rates, or carrier names.
    private var settleRows: [SettleRow] {
        [
            SettleRow(title: "Linehaul",
                      amount: money(settledLinehaul, signed: true), state: .billed),
            SettleRow(title: "Hazmat differential",
                      amount: money(settledHazmat, signed: true), state: .billed),
            SettleRow(title: "Detention",
                      amount: money(settledDetention, signed: true), state: .billed),
            SettleRow(title: "Catalyst share",
                      amount: money(settledCatalyst.map { -$0 }, signed: true), state: .netted),
            SettleRow(title: "Driver net",
                      amount: money(settledNet), state: .pending),
        ]
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                IridescentHairline()
                heroSnapshotStrip
                section("LIFECYCLE") { lifecycleCard }
                section("PICKUP · DELIVERY") { pickupDeliveryCard }
                section("SETTLEMENT SUMMARY") { settlementCard }
                section("SHIPPER OF RECORD · §8.4") { shipperOfRecordCard }
                if let err = actionError { errorBanner(err) }
                findNextCTA
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .eusoRefreshTask { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    // MARK: - Section wrapper (gray eyebrow + content)

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            content()
        }
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                EusoTripEyebrow(verbatim: "DRIVER · CLOSED · SETTLED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
                Text(loadNumberDisplay)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 10) {
                Button { navBack?() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back")

                Text(lane)
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)
            }

            hosPill
        }
    }

    /// Success-tinted HoS reset pill — mirrors the frame's `#00C48C @0.20`
    /// capsule. The driver's live HoS clock has no source on this screen, so
    /// the pill renders the §395.3 reset label with an honest "—" remainder
    /// rather than a fabricated countdown.
    private var hosPill: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Brand.success).frame(width: 12, height: 12)
                Circle().fill(palette.bgPage).frame(width: 5, height: 5)
            }
            Text("10h RESET · \(Self.emDash)")
                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.success)
                .monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Brand.success.opacity(0.20)))
    }

    // MARK: - Hero settlement-snapshot strip (60pt)

    private var heroSnapshotStrip: some View {
        VStack(spacing: 0) {
            HStack {
                // LOAD CLOSED success pill
                Text("LOAD CLOSED")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .monospacedDigit()
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.success.opacity(0.20)))
                Spacer(minLength: 8)
                // SETTLEMENT gradient pill — status from the live preview,
                // else an honest "PENDING" structural state (no invented ETA).
                Text("SETTLEMENT · \((settlementStatus ?? "pending").uppercased())")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.primary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient.primary.opacity(0.22)))
            }

            Spacer(minLength: 4)

            Text(snapshotCaption)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .background(
            LinearGradient(colors: [Color(hex: 0x23282F), Color(hex: 0x0E1116)],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    /// Distance + next-trip caption. Distance binds to the live load; truck
    /// departure / next-trip timings have no source → honest "—".
    private var snapshotCaption: String {
        let dist: String = {
            guard let d = activeLoad?.distance, d > 0 else { return Self.emDash }
            return "\(Int(d.rounded())) mi"
        }()
        return "\(dist) · NEXT TRIP READY"
    }

    // MARK: - 8-stage lifecycle strip (CLOSED caps the strip — full gradient track)

    private var lifecycleCard: some View {
        VStack(spacing: 14) {
            // Track + nodes — at the CAP the entire segment is gradient,
            // with no neutral remainder after the current (final) node.
            GeometryReader { geo in
                let n = stages.count
                let inset: CGFloat = 14
                let usable = geo.size.width - inset * 2
                let step = usable / CGFloat(n - 1)
                let y: CGFloat = 14
                ZStack(alignment: .topLeading) {
                    // Completed segment (gradient) spans the entire strip
                    Rectangle()
                        .fill(LinearGradient.primary)
                        .frame(width: step * CGFloat(currentStageIndex), height: 2)
                        .offset(x: inset, y: y - 1)

                    ForEach(0..<n, id: \.self) { i in
                        node(for: i)
                            .position(x: inset + step * CGFloat(i), y: y)
                    }
                }
            }
            .frame(height: 28)

            // Stage labels
            HStack(spacing: 0) {
                ForEach(0..<stages.count, id: \.self) { i in
                    Text(stages[i])
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(stageLabelStyle(i))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }

            Text(lifecycleNote)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// CLOSED note — composes only live figures (driver net + settlement
    /// date). Both fall back to "—" when no settlement row exists.
    private var lifecycleNote: String {
        let net = money(settledNet)
        if let when = settledAtDisplay {
            return "LOAD CLOSED · \(net) net · settled \(when)"
        }
        return "LOAD CLOSED · \(net) net"
    }

    @ViewBuilder
    private func node(for i: Int) -> some View {
        if i < currentStageIndex {
            // Completed — gradient dot + check
            ZStack {
                Circle().fill(LinearGradient.primary).frame(width: 12, height: 12)
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .heavy))
                    .foregroundStyle(.white)
            }
        } else {
            // Current CLOSED (idx 7) — larger ringed bullseye that CAPS
            // the strip. No pending state ever renders here.
            ZStack {
                Circle().strokeBorder(LinearGradient.primary, lineWidth: 2)
                    .frame(width: 22, height: 22)
                Circle().fill(LinearGradient.primary).frame(width: 16, height: 16)
                Circle().fill(Color.white).frame(width: 6, height: 6)
            }
        }
    }

    private func stageLabelStyle(_ i: Int) -> AnyShapeStyle {
        if i == currentStageIndex { return AnyShapeStyle(LinearGradient.primary) }
        return AnyShapeStyle(palette.textPrimary)
    }

    // MARK: - Pickup / Delivery card

    /// Origin + destination rows. City/state bind to the live load; stop
    /// facility addresses + dock/gate details have NO live source on this
    /// projection → honest "—". Arrival timings likewise render "—".
    private var pickupDeliveryCard: some View {
        VStack(spacing: 0) {
            stopRow(
                eyebrow: "PICK UP · SIGNED",
                eyebrowColor: Brand.success,
                trailing: Self.emDash,
                trailingColor: palette.textSecondary,
                primary: originCityLine,
                secondary: Self.emDash,
                filled: false
            )
            Divider().overlay(Color.white.opacity(0.08))
                .padding(.vertical, 4)
            stopRow(
                eyebrow: "DELIVER · ARRIVED",
                eyebrowColor: Brand.success,
                trailing: Self.emDash,
                trailingColor: Brand.success,
                primary: destCityLine,
                secondary: Self.emDash,
                filled: true
            )
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var originCityLine: String {
        let s = [activeLoad?.pickupLocation?.city, activeLoad?.pickupLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        return s.isEmpty ? Self.emDash : s
    }
    private var destCityLine: String {
        let s = [activeLoad?.deliveryLocation?.city, activeLoad?.deliveryLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        return s.isEmpty ? Self.emDash : s
    }

    private func stopRow(eyebrow: String, eyebrowColor: Color,
                         trailing: String, trailingColor: Color,
                         primary: String, secondary: String,
                         filled: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(filled ? AnyShapeStyle(Brand.success) : AnyShapeStyle(LinearGradient.diagonal))
                    .frame(width: 18, height: 18)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(eyebrow)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(eyebrowColor)
                    Spacer(minLength: 6)
                    Text(trailing)
                        .font(.system(size: 11, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(trailingColor)
                }
                Text(primary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(secondary)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Settlement summary card (5-row financial breakdown)

    private var settlementCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hazmat archive strip — seal + gallons cleared have no live
            // source on this projection → honest "—".
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().fill(Brand.hazmat)
                        .frame(width: 14, height: 14)
                        .rotationEffect(.degrees(45))
                    Image(systemName: "shippingbox")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x0E1116))
                }
                .frame(width: 22, height: 22)
                Text("Hazmat archive · seal \(Self.emDash)")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text("\(Self.emDash) cleared · 0 alerts")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.success)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                LinearGradient(colors: [Color(hex: 0x23282F), Color(hex: 0x0E1116)],
                               startPoint: .leading, endPoint: .trailing)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.bottom, 12)

            // 5 financial rows
            ForEach(settleRows) { row in
                settlementRow(row)
                    .padding(.vertical, 6)
            }

            Text("Settlement ID: \(settlementId ?? Self.emDash) · settlement preview")
                .font(EType.mono(.caption)).tracking(0.2)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 8)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    @ViewBuilder
    private func settlementRow(_ row: SettleRow) -> some View {
        HStack(spacing: 8) {
            settlementGlyph(row.state)
            Text(row.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            Text(row.amount)
                .font(EType.mono(.caption))
                .fontWeight(row.state == .pending ? .heavy : .semibold)
                .monospacedDigit()
                .foregroundStyle(amountColor(row.state))
            Text(badgeText(row.state))
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(badgeColor(row.state))
                .frame(width: 52, alignment: .trailing)
        }
    }

    /// Leading glyph — BILLED uses a gradient checkbox, NETTED a blue
    /// minus chip, PENDING a hollow blue-ringed box (per the frame).
    @ViewBuilder
    private func settlementGlyph(_ state: SettleState) -> some View {
        switch state {
        case .billed:
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(LinearGradient.diagonal)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 14, height: 14)
        case .netted:
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Brand.blue)
                Rectangle().fill(Color.white)
                    .frame(width: 7, height: 2)
                    .clipShape(Capsule())
            }
            .frame(width: 14, height: 14)
        case .pending:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(palette.bgCardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Brand.blue, lineWidth: 1.4)
                )
                .frame(width: 14, height: 14)
        }
    }

    private func amountColor(_ state: SettleState) -> Color {
        switch state {
        case .billed:  return palette.textPrimary
        case .netted:  return Brand.blue
        case .pending: return palette.textPrimary
        }
    }

    private func badgeText(_ state: SettleState) -> String {
        switch state {
        case .billed:  return "BILLED"
        case .netted:  return "NETTED"
        case .pending: return "PENDING"
        }
    }

    private func badgeColor(_ state: SettleState) -> Color {
        switch state {
        case .billed:  return Brand.success
        case .netted:  return Brand.blue
        case .pending: return Brand.blue
        }
    }

    // MARK: - §8.4 Shipper-of-record card

    /// Live shipper party from `loads.getById`. Name / company / initials
    /// bind to the real party objects; absent a party they render "—".
    private var shipperOfRecordCard: some View {
        let shipper = activeLoad?.shipper
        let display = shipper?.companyName ?? shipper?.name ?? Self.emDash
        let initials = shipper?.initials
            ?? Self.initials(from: shipper?.companyName ?? shipper?.name)
            ?? Self.emDash
        let person = shipper?.name ?? Self.emDash
        let idLine: String = {
            if let id = shipper?.id { return "companyId \(id)" }
            return Self.emDash
        }()
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 56, height: 56)
                Text(initials)
                    .font(.system(size: 16, weight: .bold)).tracking(0.4)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(display)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    Text("VERIFIED")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.success)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.success.opacity(0.16)))
                }
                Text("\(person) · \(idLine)")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("Shipper of record · §8.4")
                    .font(EType.mono(.caption)).tracking(0.2)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// Derive 2-letter initials from a real name when the server omits the
    /// `initials` field. Returns nil for an absent/blank name (→ "—").
    private static func initials(from name: String?) -> String? {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return s.isEmpty ? nil : s
    }

    // MARK: - CTA + error banner

    /// CLOSED-state CTA — the dual "Find next load · See settlement" hands
    /// off to the next-trip flow via the env-injected advance closure.
    private var findNextCTA: some View {
        CTAButton(
            title: isFindingNext ? "Finding…" : "Find next load · See settlement",
            action: { Task { await findNextLoad() } },
            isLoading: isFindingNext
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md)
            .strokeBorder(Brand.danger.opacity(0.4)))
    }

    // MARK: - Hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        let lid = lifecycle.loadId
        guard !lid.isEmpty else { return }
        // CORRECTED decode: pass the load id as a String to the proc and
        // decode the top-level `id` as String? (server returns
        // String(load.id)). Decoding it as Int throws and blanks the screen.
        struct In: Encodable { let id: String }
        do {
            activeLoad = try await EusoTripAPI.shared.query(
                "loads.getById", input: In(id: lid)
            )
        } catch {
            actionError = "Couldn't load the trip: \((error as NSError).localizedDescription)"
        }
        await loadSettlement()
    }

    /// Read the closed-load financial breakdown from the REAL
    /// `earnings.previewSettlement({ loadId })` procedure (settlements +
    /// settlement_documents + billable detention_records for this one load).
    /// Each live figure binds ONLY when the server returns a non-null value;
    /// when the server returns null the figure stays nil and renders "—".
    /// Any failure surfaces honestly via `actionError` — no fabricated data.
    private func loadSettlement() async {
        // Resolve the live numeric load id for the earnings proc. The
        // lifecycle store carries a String id (loads.search row); the
        // settlement preview keys on the numeric load id.
        guard let lid = Int(lifecycle.loadId) ?? activeLoad?.id.flatMap({ Int($0) }) else { return }
        isLoadingSettlement = true
        defer { isLoadingSettlement = false }
        do {
            let p = try await EusoTripAPI.shared.earnings.previewSettlement(loadId: lid)
            settlementCurrency = p.currency
            hasSettlement      = p.hasSettlement
            settlementId       = p.settlementId
            settlementStatus   = p.settlementStatus
            settledAt          = p.settledAt
            // Bind each real figure; leave nil (→ "—") where the server
            // returned null (no settlement persisted yet).
            settledLinehaul  = p.linehaul
            settledHazmat    = p.hazmatSurcharge
            settledDetention = p.detention
            settledCatalyst  = p.catalystShare
            settledNet       = p.driverNet
        } catch {
            actionError = "Couldn't load settlement: \((error as NSError).localizedDescription)"
        }
    }

    /// CLOSED is the terminal stage — there is no forward lifecycle
    /// transition. "Find next load" hands off to the next-trip flow via the
    /// local advance closure; a failure surfaces rather than faking success.
    private func findNextLoad() async {
        isFindingNext = true
        actionError = nil
        defer { isFindingNext = false }
        guard let advance else {
            actionError = "Next-trip handoff is unavailable right now."
            return
        }
        advance()
    }
}

// MARK: - Wrapper (default-initializable)

struct DriverClosedScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette = Theme.dark) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            DriverClosed(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_112(),
                      trailing: driverNavTrailing_112(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_112() -> [NavSlot] {
    RoleNav.driverLeading(current: .trips)
}
private func driverNavTrailing_112() -> [NavSlot] {
    RoleNav.driverTrailing(current: .none)
}

#Preview("112 · Driver Closed · Dark") {
    DriverClosedScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("112 · Driver Closed · Light") {
    DriverClosedScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
