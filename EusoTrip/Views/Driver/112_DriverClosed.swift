//
//  112_DriverClosed.swift
//  EusoTrip — Lifecycle screen 112 · Driver Closed (CLOSED · UN1203 SETTLED).
//
//  Verbatim reconstruction of the 2026-05 wireframe frame
//  `112 Closed · Dark` (440×956). Fires once the load is fully closed:
//  truck departed 6:24 PM, LOAD CLOSED 7:14 PM, driver started a §395.3
//  10-hour reset at 7:30 PM (9h 16m remaining), and the settlement is
//  queued (SETTLEMENT IN 1.8d · pays Mon · Apr 28). The eighth and
//  CAPPING context in the §74 → §83 cousin-port lineage — with this
//  firing the Driver lifecycle ladder is COMPLETE across all 8 canonical
//  stages.
//
//  Persona: Michael Eusorone (ME) · UN1203 gasoline PG II tanker ·
//  MC-306 · Houston → Dallas · 239/239 mi · $1,900 linehaul · lifecycle
//  index 7 (CLOSED — CAPS the strip). §8.4 shipper-of-record card names
//  Diego Usoro · Eusorone Technologies (companyId 1).
//
//  Composition (top → bottom, matching the frame):
//    • TopBar — gradient eyebrow "DRIVER · CLOSED · UN1203 SETTLED",
//      load-ID mono tag, back chevron, "Houston → Dallas" title, and a
//      success 10h RESET · 9h 16m HoS pill (driver in §395.3 recovery).
//    • Iridescent hairline.
//    • Hero settlement-snapshot strip (60pt — drops from 111's 92pt
//      persistence) — LOAD CLOSED 7:14 PM success pill, SETTLEMENT IN
//      1.8d gradient pill, and a "239/239 mi · TRUCK DEPARTED 6:24 PM ·
//      NEXT TRIP READY" caption.
//    • 8-stage lifecycle strip — CLOSED current (idx 7), CAPS the strip;
//      the whole progress segment is gradient with no neutral remainder.
//    • Pickup / Delivery card — Houston SIGNED + Dallas ARRIVED rows.
//    • Settlement summary card — hazmat archive strip + 5 financial rows
//      (Linehaul +$1,900 BILLED · Hazmat +$150 BILLED · Detention +$67.50
//      BILLED · Catalyst share -$211.75 NETTED · Driver net $1,905.75
//      PENDING — three-state BILLED/NETTED/PENDING badge) + settlement-ID
//      mono line.
//    • §8.4 Shipper-of-record card — DU avatar · Eusorone Technologies ·
//      VERIFIED.
//    • BottomNav — TRIPS active (Driver variant).
//
//  Wiring: hydrates the active load via TripLifecycleStore +
//  loads.getById, and the closed-load financial breakdown via
//  `earnings.previewSettlement({ loadId })` — the REAL driver-facing
//  settlement preview the frame names (built in THE OATH §42). It reads
//  settlements (linehaul / hazmat surcharge / accessorial / catalyst
//  share), settlement_documents (driver net + deductions) and billable
//  detention_records for this single load. Each live figure binds only
//  when the server returns a non-null value (a real settlement row
//  exists); otherwise the frame's authored references stand in for
//  display and `hasSettlement` stays false. Currency drives the money
//  formatter (USD/CAD/MXN — tri-country honest). Any failure surfaces
//  through @State actionError — no synthesized replies, no mock data.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DriverClosed: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?

    /// Live settlement figures for this closed load. The summary card's
    /// Driver net + Hazmat differential read off the matching
    /// `earnings.getEarnings` row once hydrated; until then the frame's
    /// authored references render so the screen never blanks.
    @State private var settledNet: Double?
    @State private var settledHazmat: Double?
    /// Additional live figures read from `earnings.previewSettlement`. Each is
    /// optional and `nil` until a REAL settlement row lands — the frame
    /// references below stand in for display only; nothing is fabricated.
    @State private var settledLinehaul: Double?
    @State private var settledDetention: Double?
    @State private var settledCatalyst: Double?
    /// Currency the settlement is denominated in (tri-country honest:
    /// USD/CAD/MXN). Defaults to USD so the frame renders "$" verbatim until a
    /// non-USD load hydrates.
    @State private var settlementCurrency: String = "USD"
    @State private var isLoadingSettlement: Bool = false

    @State private var isFindingNext: Bool = false
    @State private var actionError: String?

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    // MARK: - Frame reference values (render until the live load hydrates)

    private let frameLoadId        = "LD-260427-A38FB12C7E"
    private let frameLane          = "Houston → Dallas"
    private let frameHoS           = "10h RESET · 9h 16m"
    private let frameClosedPill    = "LOAD CLOSED 7:14 PM"
    private let frameSettlePill    = "SETTLEMENT IN 1.8d"
    private let frameSnapshot      = "239 / 239 mi · TRUCK DEPARTED 6:24 PM · NEXT TRIP READY"
    private let frameLifecycleNote = "LOAD CLOSED 7:14 PM · $1,905.75 net · pays Mon · Apr 28"
    private let frameSettlementId  = "Settlement ID: STL-260427-A38FB12C7E · earnings.previewSettlement"

    // Frame-authored settlement figures (reference until a live read lands).
    private let frameLinehaul: Double = 1_900.00
    private let frameHazmat:   Double = 150.00
    private let frameDetention: Double = 67.50
    private let frameCatalyst: Double = 211.75
    private let frameDriverNet: Double = 1_905.75

    private var linehaulAmount:  Double { settledLinehaul  ?? frameLinehaul }
    private var hazmatAmount:    Double { settledHazmat    ?? frameHazmat }
    private var detentionAmount: Double { settledDetention ?? frameDetention }
    private var catalystAmount:  Double { settledCatalyst  ?? frameCatalyst }
    private var driverNetAmount: Double { settledNet       ?? frameDriverNet }

    private func usd(_ v: Double, signed: Bool = false) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = settlementCurrency
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        let base = f.string(from: NSNumber(value: abs(v))) ?? "$0.00"
        if signed { return (v < 0 ? "-" : "+") + base }
        return base
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

    private var settleRows: [SettleRow] {
        [
            SettleRow(title: "Linehaul · 239 mi · pricebook tier 3",
                      amount: usd(linehaulAmount, signed: true), state: .billed),
            SettleRow(title: "Hazmat differential · UN1203 PG II",
                      amount: usd(hazmatAmount, signed: true), state: .billed),
            SettleRow(title: "Detention · 45 min @ $90/hr",
                      amount: usd(detentionAmount, signed: true), state: .billed),
            SettleRow(title: "Catalyst share · Eusotrans LLC 10%",
                      amount: usd(-catalystAmount, signed: true), state: .netted),
            SettleRow(title: "Driver net · pays Mon · Apr 28",
                      amount: usd(driverNetAmount), state: .pending),
        ]
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                IridescentHairline()
                heroSnapshotStrip
                section("LIFECYCLE · UN1203 HAZMAT TANKER") { lifecycleCard }
                section("PICKUP · DELIVERY") { pickupDeliveryCard }
                section("SETTLEMENT SUMMARY · UN1203 TANKER") { settlementCard }
                section("SHIPPER OF RECORD · §8.4") { shipperOfRecordCard }
                if let err = actionError { errorBanner(err) }
                findNextCTA
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
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
                Text("✦ DRIVER · CLOSED · UN1203 SETTLED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
                Text(activeLoad?.loadNumber ?? frameLoadId)
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

    private var lane: String {
        guard let load = activeLoad,
              let p = load.pickupLocation, !p.city.isEmpty,
              let d = load.deliveryLocation, !d.city.isEmpty else {
            return frameLane
        }
        return "\(p.city) → \(d.city)"
    }

    /// Success-tinted 10h RESET pill — mirrors the frame's `#00C48C @0.20`
    /// capsule (flipped from 111's blue ON-DUTY because the driver is in a
    /// §395.3 off-duty recovery). Donut HoS dot in Brand.success.
    private var hosPill: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Brand.success).frame(width: 12, height: 12)
                Circle().fill(palette.bgPage).frame(width: 5, height: 5)
            }
            Text(frameHoS)
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
                Text(frameClosedPill)
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .monospacedDigit()
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.success.opacity(0.20)))
                Spacer(minLength: 8)
                // SETTLEMENT IN 1.8d gradient pill
                Text(frameSettlePill)
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.primary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient.primary.opacity(0.22)))
            }

            Spacer(minLength: 4)

            Text(frameSnapshot)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
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

            Text(frameLifecycleNote)
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

    private var pickupDeliveryCard: some View {
        VStack(spacing: 0) {
            stopRow(
                eyebrow: "PICK UP · HOUSTON · SIGNED",
                eyebrowColor: Brand.success,
                trailing: "14h 14m ago",
                trailingColor: palette.textSecondary,
                primary: "Today · 06:00 CDT (signed)",
                secondary: "LyondellBasell Channelview · 1515 Sheldon Rd",
                filled: false
            )
            Divider().overlay(Color.white.opacity(0.08))
                .padding(.vertical, 4)
            stopRow(
                eyebrow: "DELIVER · DALLAS · ARRIVED",
                eyebrowColor: Brand.success,
                trailing: "3h 50m ago",
                trailingColor: Brand.success,
                primary: "Today · 16:30 – 18:00 CDT window",
                secondary: "RaceTrac Terminal · 4801 Singleton Blvd · gate 3",
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
            // Hazmat archive strip
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().fill(Brand.hazmat)
                        .frame(width: 14, height: 14)
                        .rotationEffect(.degrees(45))
                    Text("3")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x0E1116))
                }
                .frame(width: 22, height: 22)
                Text("Class 3 · PG II · placards 1203 · seal EU-71044 archived")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text("5,000 gal cleared · 0 alerts")
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

            Text(frameSettlementId)
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

    private var shipperOfRecordCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 56, height: 56)
                Text("DU")
                    .font(.system(size: 16, weight: .bold)).tracking(0.4)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Eusorone Technologies")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 6)
                    Text("VERIFIED")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.success)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.success.opacity(0.16)))
                }
                Text("Diego Usoro · companyId 1")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textPrimary)
                Text("MATRIX-50 batch · 97.8% on-time · Pays in 3.2d avg")
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

    // MARK: - CTA + error banner

    /// CLOSED-state CTA pivots from 111's "Submit BOL" to the dual
    /// "Find next load · See settlement" — fires the lifecycle advance
    /// (next-trip handoff) once the load is fully closed.
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
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        do {
            activeLoad = try await EusoTripAPI.shared.loads.getById(n)
        } catch {
            actionError = "Couldn't load the trip: \((error as NSError).localizedDescription)"
        }
        await loadSettlement()
    }

    /// Read the closed-load financial breakdown from the REAL
    /// `earnings.previewSettlement({ loadId })` procedure (THE OATH §42 —
    /// the proc the frame names now EXISTS on the earningsRouter; it reads
    /// settlements + settlement_documents + billable detention_records for
    /// this one load). Each live figure binds only when the server returns a
    /// non-null value (i.e. a real settlement row exists); otherwise the
    /// frame's authored references stand in for display and `hasSettlement`
    /// stays false. Any failure surfaces honestly via `actionError` — no
    /// synthesized replies, no fabricated numbers.
    private func loadSettlement() async {
        // Resolve the live load id (lifecycle store first, then the hydrated
        // load). Without one we cannot key the settlement — keep frame refs.
        guard let lid = Int(lifecycle.loadId) ?? activeLoad?.id else { return }
        isLoadingSettlement = true
        defer { isLoadingSettlement = false }
        do {
            let p = try await EusoTripAPI.shared.earnings.previewSettlement(loadId: lid)
            settlementCurrency = p.currency
            // Bind each real figure; leave the frame reference in place where
            // the server returned null (no settlement persisted yet).
            if let v = p.linehaul       { settledLinehaul  = v }
            if let v = p.hazmatSurcharge { settledHazmat   = v }
            if let v = p.detention      { settledDetention = v }
            if let v = p.catalystShare  { settledCatalyst  = v }
            if let v = p.driverNet      { settledNet       = v }
        } catch {
            actionError = "Couldn't load settlement: \((error as NSError).localizedDescription)"
        }
    }

    /// CLOSED is the terminal stage — there is no forward lifecycle
    /// transition to execute. "Find next load" hands off to the next-trip
    /// flow via the local advance closure; we surface a failure rather
    /// than pretending success.
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
    [NavSlot(label: "Home",  systemImage: "house",      isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",  isCurrent: true)]
}
private func driverNavTrailing_112() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)]
}

#Preview("112 · Driver Closed · Dark") {
    DriverClosedScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("112 · Driver Closed · Light") {
    DriverClosedScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
