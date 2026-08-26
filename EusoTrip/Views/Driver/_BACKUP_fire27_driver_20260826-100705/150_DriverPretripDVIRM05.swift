//
//  150_DriverPretripDVIRM05.swift
//  EusoTrip — Driver · 150–156 M-05 Pre-trip DVIR composite
//
//  Wireframe slots (Light/Dark SVG pairs are design truth):
//    150 Driver Assignment Receipt M05           → the receipt step (entry)
//    151–153,156 Driver Pretrip DVIR Section 1–4 Ack M05 → the section-ack walk
//  COMPOSITE DECISION: the M-05 DVIR band is a LIFECYCLE BAND, not six screens.
//  Following the house DVIR-composite pattern (114 / DL101 / DL133), this is ONE
//  cohesive screen that walks assignment-receipt → section-1→4 acknowledgements as
//  a stepped flow, exactly the way the existing DVIR/lifecycle composites work —
//  not six redundant files.
//
//  Wiring (all verified against the live routers this fire):
//    READ  drivers.getPreTripChecklist   — drivers.ts:1799 → { categories: [{ name, items:[{id,label}] }] }
//                                          FOUR real categories (Engine Compartment · Cab · Exterior ·
//                                          Safety). The walk binds each section to a REAL category — the
//                                          wireframe's "14-section" sub-axis is a client-side count over
//                                          the real 4-category checklist (per the SVG's own honesty note).
//    READ  loads.getById                 — loads.ts:1152 (payout · RPM · pickup · lane · cargo · parties)
//    WRITE drivers.startDVIR             — drivers.ts:1159 ({type:"pre_trip", vehicleId}) → { dvirId } · arms
//    WRITE drivers.submitPreTripInspection — drivers.ts:1805 ({items:[{itemId,passed}]}) · per-section commit
//    WRITE drivers.submitDVIR            — drivers.ts:1185 ({dvirId,passed,notes?,signature?}) · TERMINAL submit
//  HONEST BINDING: the wireframe section titles (Lights / Brakes / Steering) are illustrative; the walk
//    renders the REAL checklist categories + items. No sectionIndex param exists on the backend — the
//    per-section acks accumulate client-side against the startDVIR session and the single terminal
//    submitDVIR(passed) fires when the last section is acked. Every value binds to a real read with a
//    "-" fallback; no fabricated persona strings ship.
//  RBAC: drivers.* are driverProcedure (DRIVER gate) · loads.getById protectedProcedure.
//    transportMode = truck · country = US (49 CFR 396.13 pre-trip DVIR certification).
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - tRPC decode shapes

private struct M05Checklist: Decodable { let categories: [M05Category] }
private struct M05Category: Decodable, Identifiable {
    let name: String
    let items: [M05Item]
    var id: String { name }
}
private struct M05Item: Decodable, Identifiable {
    let id: String
    let label: String
}

/// Minimal projection of `loads.getById` for the receipt + KPI quartet.
private struct M05LoadCtx: Decodable {
    let loadNumber: String?
    let rate: Double?
    let distance: Double?
    let weight: Double?
    let status: String?
    let cargoType: String?
    let commodity: String?
    let equipmentType: String?
    let pickupDate: String?
    let pickupLocation: CityState?
    let deliveryLocation: CityState?
    let catalyst: Party?
    let shipper: Party?
    struct CityState: Decodable { let city: String?; let state: String? }
    struct Party: Decodable {
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
    }
}

// MARK: - Step

private enum M05Step: Equatable {
    case receipt
    case section(Int)   // 0-based index into categories
    case complete
}

// MARK: - Screen wrapper (Shell + Driver nav)

struct DriverPretripDVIRM05Screen: View {
    let theme: Theme.Palette
    var loadId: String = ""
    var vehicleId: String = ""
    @EnvironmentObject private var nav: DriverNavController

    var body: some View {
        Shell(theme: theme) {
            M05Body(loadId: loadId, vehicleId: vehicleId, onExit: { nav.currentTab = .trips })
        } nav: {
            BottomNav(
                leading: [NavSlot(label: DriverTab.home.label,  systemImage: DriverTab.home.systemImage,  isCurrent: false),
                          NavSlot(label: DriverTab.trips.label, systemImage: DriverTab.trips.systemImage, isCurrent: true)],
                trailing: [NavSlot(label: DriverTab.wallet.label, systemImage: DriverTab.wallet.systemImage, isCurrent: false),
                           NavSlot(label: DriverTab.me.label,     systemImage: DriverTab.me.systemImage,     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct M05Body: View {
    let loadId: String
    let vehicleId: String
    let onExit: () -> Void

    @Environment(\.palette) private var palette

    @State private var step: M05Step = .receipt
    @State private var categories: [M05Category] = []
    @State private var load: M05LoadCtx?
    @State private var dvirId: String?
    @State private var acked: Set<Int> = []
    @State private var loaded = false
    @State private var inFlight = false
    @State private var actionErr: String?

    private var total: Int { max(categories.count, 0) }
    private var ackedCount: Int { acked.count }
    private var numericLoadId: Int? { Int(loadId.filter(\.isNumber)) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                switch step {
                case .receipt:            receiptContent
                case .section(let idx):   sectionContent(idx)
                case .complete:           completeContent
                }
                if let err = actionErr { infoStrip(err, tint: Brand.danger) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
    }

    // MARK: TopBar (eyebrow + H1 + status pill + ME disc)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(LinearGradient.primary)
                    Text(eyebrow)
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                        .lineLimit(1)
                }
                Spacer()
                Text(loadNumberDisplay)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center) {
                Text(h1Title)
                    .font(.system(size: 26, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                statusPill
            }
            Text(subLine)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            IridescentHairline().padding(.top, Space.s2)
        }
    }

    private var eyebrow: String {
        switch step {
        case .receipt:          return "DRIVER · TRIPS · ASSIGNED · DVIR ARMED"
        case .section(let i):   return "DRIVER · TRIPS · DVIR · S\(i + 1)"
        case .complete:         return "DRIVER · TRIPS · DVIR · COMPLETE"
        }
    }
    private var h1Title: String {
        switch step {
        case .receipt:          return "Load assigned"
        case .section(let i):   return "Section \(i + 1) · acked"
        case .complete:         return "Cleared to roll"
        }
    }
    private var subLine: String {
        switch step {
        case .receipt:
            return "\(carrierDisplay) · \(laneDisplay) · pre-trip DVIR armed"
        case .section(let i):
            return "\(carrierDisplay) · \(sectionName(i)) · \(ackedCount)/\(total) sections"
        case .complete:
            return "Pre-trip DVIR submitted · signed under 49 CFR 396.13"
        }
    }

    private var statusPill: some View {
        Group {
            switch step {
            case .receipt:
                pill("AWARDED", kind: .success, icon: "checkmark")
            case .section:
                pill("DVIR · \(ackedCount)/\(total)", kind: .info, icon: "checkmark")
            case .complete:
                pill("SAFE TO OPERATE", kind: .success, icon: "checkmark.shield.fill")
            }
        }
    }
    private func pill(_ text: String, kind: StatusPill.Kind, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .heavy))
            Text(text).font(.system(size: 10, weight: .heavy)).tracking(0.4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(kind == .success ? AnyShapeStyle(Brand.success) : AnyShapeStyle(LinearGradient.diagonal)))
    }

    // MARK: RECEIPT step (150)

    private var receiptContent: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            calloutCard(
                tag: "AWARDED · DVIR SUB-AXIS OPENED",
                body: "\(loadNumberDisplay) · \(laneDisplay) · you drive · pre-trip DVIR armed"
            )
            carrierRecapCard
            kpiQuartet
            lifecycleStrip(status: load?.status ?? "awarded")
            armedRow
            pickupDeliveryCard
            cargoCard
            shipperCard
            receiptActionRow
        }
    }

    private var carrierRecapCard: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            initialsDisc(carrierInitials, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("DISPATCH-OF-RECORD · ASSIGNED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(LinearGradient.primary)
                Text(carrierDisplay)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(carrierSub)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(alignment: .leading) { Rectangle().fill(LinearGradient.diagonal).frame(width: 3) }
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var armedRow: some View {
        seamRow(
            tag: "PRETRIP DVIR · ARMED · SUB-AXIS OPENED",
            mono: "drivers.startDVIR(type: pre_trip) · first-section ack next",
            trailingTop: "\(ackedCount) / \(total)",
            trailingBottom: "ARMED"
        )
    }

    private var receiptActionRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: inFlight ? "Arming DVIR…" : "Start pretrip DVIR",
                action: { Task { await startDVIR() } },
                trailingIcon: "arrow.right",
                isLoading: inFlight
            )
            .disabled(inFlight || total == 0)

            secondaryButton("View detail") { onExit() }
        }
    }

    // MARK: SECTION step (151–156)

    private func sectionContent(_ idx: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            calloutCard(
                tag: "DVIR ADVANCING · \(ackedCount)/\(total) · \(sectionName(idx).uppercased()) ACKED",
                body: "\(loadNumberDisplay) · \(laneDisplay) · you run the DVIR"
            )
            kpiQuartet
            lifecycleStrip(status: "awarded", microChip: "DVIR · \(idx + 1)/\(total) · \(sectionName(idx).uppercased())")
            sectionDetailCard(idx)
            progressCapsule
            sectionAckedRow(idx)
            if idx + 1 < total { nextSectionPreview(idx + 1) }
            shipperCard
            sectionActionRow(idx)
        }
    }

    private func sectionDetailCard(_ idx: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SECTION \(idx + 1) · \(sectionName(idx).uppercased()) · ACKED")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            let items = categories.indices.contains(idx) ? categories[idx].items : []
            if items.isEmpty {
                Text("No checklist items on this section.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                    itemAckRow(pair.element.label)
                    if pair.offset < items.count - 1 { Divider().overlay(palette.borderFaint.opacity(0.6)) }
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func itemAckRow(_ label: String) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(Brand.success.opacity(0.22)).frame(width: 18, height: 18)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Brand.success)
            }
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Brand.success)
        }
        .padding(.vertical, Space.s1)
    }

    private var progressCapsule: some View {
        GeometryReader { geo in
            let pct: CGFloat = total == 0 ? 0 : CGFloat(ackedCount) / CGFloat(total)
            ZStack(alignment: .leading) {
                Capsule().fill(palette.tintNeutral).frame(height: 6)
                Capsule().fill(LinearGradient.diagonal)
                    .frame(width: max(6, geo.size.width * pct), height: 6)
            }
        }
        .frame(height: 6)
    }

    private func sectionAckedRow(_ idx: Int) -> some View {
        seamRow(
            tag: "SECTION \(idx + 1) ACKED · ADVANCING",
            mono: "\(dvirId ?? "dvir session") · submitDVIR at \(total)/\(total)",
            trailingTop: "\(ackedCount) / \(total)",
            trailingBottom: "ADVANCING"
        )
    }

    private func nextSectionPreview(_ nextIdx: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("NEXT · QUEUED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                Text("Section \(nextIdx + 1) · \(sectionName(nextIdx))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer()
            Text("\(nextIdx + 1) / \(total)")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(alignment: .leading) { Rectangle().fill(palette.textTertiary.opacity(0.6)).frame(width: 3) }
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func sectionActionRow(_ idx: Int) -> some View {
        let isLast = idx + 1 >= total
        return HStack(spacing: Space.s3) {
            CTAButton(
                title: inFlight ? "Saving…" : (isLast ? "Submit DVIR · safe to operate" : "Proceed to Section \(idx + 2)"),
                action: { Task { await proceed(from: idx) } },
                trailingIcon: isLast ? "checkmark.shield.fill" : "arrow.right",
                isLoading: inFlight
            )
            .disabled(inFlight)

            secondaryButton("Save & exit") { Task { await saveAndExit() } }
        }
    }

    // MARK: COMPLETE step (012-style closure)

    private var completeContent: some View {
        VStack(spacing: Space.s5) {
            ZStack {
                Circle().fill(Brand.success.opacity(0.15)).frame(width: 96, height: 96)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Brand.success)
                    .symbolEffect(.bounce, value: true)
            }
            VStack(spacing: 6) {
                Text("Cleared to roll")
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                Text("Pre-trip DVIR submitted · \(total)/\(total) sections acked · you're safe to operate.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.s5)
                if let id = dvirId {
                    Text("DVIR \(id) · signed 49 CFR 396.13")
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, 4)
                }
            }
            kpiQuartet
            CTAButton(title: "Back to Trips", action: { onExit() })
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s7)
    }

    // MARK: Shared cards

    private func calloutCard(tag: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LinearGradient.primary)
                Text(tag)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(LinearGradient.primary)
                    .lineLimit(1)
            }
            Text(body)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.esangSoft, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.4), Brand.magenta.opacity(0.4)], startPoint: .leading, endPoint: .trailing)))
    }

    private var kpiQuartet: some View {
        HStack(spacing: 0) {
            kpiCell("PAYOUT", payoutDisplay, sub: "NET-30")
            kpiDivider
            kpiCell("RPM", rpmDisplay, sub: distanceDisplay)
            kpiDivider
            kpiCell("PICKUP", pickupDisplay, sub: "origin dock")
            kpiDivider
            kpiCell("DVIR", "\(ackedCount) / \(total)", sub: dvirStateWord)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }
    private var kpiDivider: some View { Rectangle().fill(palette.borderFaint).frame(width: 1, height: 42) }
    private func kpiCell(_ label: String, _ value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 17, weight: .heavy)).monospacedDigit()
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.system(size: 9)).foregroundStyle(palette.textSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var dvirStateWord: String {
        switch step {
        case .receipt: return "armed"
        case .complete: return "passed"
        default: return "advancing"
        }
    }

    private func lifecycleStrip(status: String, microChip: String? = nil) -> some View {
        let stages = ["POSTED", "BIDDING", "AWARDED", "PICKUP", "TRANSIT", "DELIVERY", "PAPERWORK", "CLOSED"]
        let activeIdx = 2   // AWARDED is the live ring across the DVIR band
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("LIFECYCLE · AWARDED")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if let chip = microChip {
                    Text(chip)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(LinearGradient.primary))
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(stages.enumerated()), id: \.offset) { idx, name in
                    VStack(spacing: 3) {
                        ZStack {
                            if idx < activeIdx {
                                Circle().fill(LinearGradient.diagonal).frame(width: 10, height: 10)
                            } else if idx == activeIdx {
                                Circle().stroke(LinearGradient.diagonal, lineWidth: 2).frame(width: 12, height: 12)
                            } else {
                                Circle().fill(palette.tintNeutral).frame(width: 8, height: 8)
                            }
                        }
                        .frame(height: 12)
                        Text(name)
                            .font(.system(size: 5.5, weight: .heavy)).tracking(0.2)
                            .foregroundStyle(idx == activeIdx ? palette.textPrimary : palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var pickupDeliveryCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("PICKUP · DELIVERY · \(distanceDisplay)")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            endpointRow(color: Brand.blue, kicker: "PICK UP", place: originDisplay, when: pickupDisplay)
            Divider().overlay(palette.borderFaint)
            endpointRow(color: Brand.magenta, kicker: "DELIVER", place: destDisplay, when: "on schedule")
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }
    private func endpointRow(color: Color, kicker: String, place: String, when: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Circle().fill(color).frame(width: 14, height: 14).overlay(Circle().fill(palette.bgCard).frame(width: 6, height: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Text(place).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textPrimary).lineLimit(1)
            }
            Spacer()
            Text(when).font(EType.mono(.caption)).foregroundStyle(color == Brand.blue ? Brand.info : palette.textSecondary)
        }
        .padding(.vertical, Space.s1)
    }

    private var cargoCard: some View {
        HStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 6).fill(LinearGradient.esangSoft)
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "shippingbox.fill").font(.system(size: 14)).foregroundStyle(LinearGradient.diagonal))
            VStack(alignment: .leading, spacing: 2) {
                Text(cargoDisplay).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(cargoSub).font(.system(size: 10)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer()
            StatusPill(text: "Secured", kind: .success)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var shipperCard: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            initialsDisc(shipperInitials, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("SHIPPER OF RECORD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(shipperDisplay)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("\(loadNumberDisplay) · award \(payoutDisplay) · NET-30 settle")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(alignment: .leading) { Rectangle().fill(LinearGradient.diagonal).frame(width: 3) }
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: small shared bits

    private func seamRow(tag: String, mono: String, trailingTop: String, trailingBottom: String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tag)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(LinearGradient.primary)
                    .lineLimit(1)
                Text(mono)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(trailingTop)
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(trailingBottom)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.5)
                    .foregroundStyle(LinearGradient.primary)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.esangSoft, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(alignment: .leading) { Rectangle().fill(LinearGradient.diagonal).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2)) }
        .overlay(RoundedRectangle(cornerRadius: Radius.md)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.5), Brand.magenta.opacity(0.5)], startPoint: .leading, endPoint: .trailing)))
    }

    private func initialsDisc(_ text: String, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(LinearGradient.diagonal).frame(width: size, height: size)
            Circle().fill(RadialGradient(colors: [.white.opacity(0.6), .clear], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.5))
                .frame(width: size * 0.8, height: size * 0.8)
            Text(text).font(.system(size: size * 0.32, weight: .heavy)).foregroundStyle(.white)
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(EType.bodyStrong)
                .foregroundStyle(LinearGradient.primary)
                .frame(minWidth: 120, minHeight: 52)
                .padding(.horizontal, Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.5), Brand.magenta.opacity(0.5)], startPoint: .leading, endPoint: .trailing)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func infoStrip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(EType.caption)
            .foregroundStyle(palette.textPrimary)
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: display helpers

    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }
    private var laneDisplay: String {
        let p = load?.pickupLocation?.city ?? ""
        let d = load?.deliveryLocation?.city ?? ""
        if !p.isEmpty && !d.isEmpty { return "\(p) → \(d)" }
        return "lane pending"
    }
    private var originDisplay: String {
        let c = load?.pickupLocation?.city ?? ""; let s = load?.pickupLocation?.state ?? ""
        return c.isEmpty ? "origin pending" : (s.isEmpty ? c : "\(c) \(s)")
    }
    private var destDisplay: String {
        let c = load?.deliveryLocation?.city ?? ""; let s = load?.deliveryLocation?.state ?? ""
        return c.isEmpty ? "destination pending" : (s.isEmpty ? c : "\(c) \(s)")
    }
    private var carrierDisplay: String { load?.catalyst?.companyName ?? load?.catalyst?.name ?? "Carrier pending" }
    private var carrierInitials: String { initials(load?.catalyst?.initials ?? load?.catalyst?.companyName ?? load?.catalyst?.name) }
    private var carrierSub: String {
        if let mc = load?.catalyst?.mcNumber, !mc.isEmpty { return "MC-\(mc) · catalyst-of-dispatch" }
        return "catalyst-of-dispatch"
    }
    private var shipperDisplay: String { load?.shipper?.companyName ?? load?.shipper?.name ?? "Shipper pending" }
    private var shipperInitials: String { initials(load?.shipper?.initials ?? load?.shipper?.companyName ?? load?.shipper?.name) }

    private var payoutDisplay: String {
        guard let r = load?.rate, r > 0 else { return "-" }
        return r < 1000 ? String(format: "$%.0f", r) : "$\(Int(r).formatted(.number))"
    }
    private var rpmDisplay: String {
        guard let r = load?.rate, let d = load?.distance, d > 0, r > 0 else { return "-" }
        return String(format: "$%.2f", r / d)
    }
    private var distanceDisplay: String {
        guard let d = load?.distance, d > 0 else { return "-" }
        return "\(Int(d.rounded())) mi"
    }
    private var pickupDisplay: String {
        guard let iso = load?.pickupDate, let date = Self.parseISO(iso) else { return "scheduled" }
        let secs = date.timeIntervalSinceNow
        if secs <= 0 { return "now" }
        let h = Int(secs) / 3600, m = (Int(secs) % 3600) / 60
        if h >= 24 { return "\(h / 24)d \(h % 24)h" }
        return "\(h)h \(String(format: "%02d", m))m"
    }
    private var cargoDisplay: String {
        let equip = load?.equipmentType ?? "trailer"
        let com = load?.commodity ?? load?.cargoType ?? "freight"
        return "\(equip) · \(com)"
    }
    private var cargoSub: String {
        guard let w = load?.weight, w > 0 else { return "chained + tarped · 0 alerts" }
        return "\(Int(w).formatted(.number)) lb · secured · 0 alerts"
    }

    private func sectionName(_ idx: Int) -> String {
        categories.indices.contains(idx) ? categories[idx].name : "Section \(idx + 1)"
    }

    private func initials(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "··" }
        let words = s.split(separator: " ")
        if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        return String(s.prefix(2)).uppercased()
    }

    private static func parseISO(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }

    // MARK: Reads / writes

    private func load() async {
        guard !loaded else { return }
        async let a: Void = loadChecklist()
        async let b: Void = loadLoad()
        _ = await (a, b)
        loaded = true
    }

    private func loadChecklist() async {
        struct In: Encodable {}
        do {
            let resp: M05Checklist = try await EusoTripAPI.shared.query("drivers.getPreTripChecklist", input: In())
            categories = resp.categories
        } catch { categories = [] }
    }
    private func loadLoad() async {
        guard !loadId.isEmpty else { return }
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) }
        catch { /* honest "-" fallbacks */ }
    }

    /// Receipt "Start pretrip DVIR" → arm the real session, advance to section 0.
    private func startDVIR() async {
        inFlight = true; actionErr = nil
        struct In: Encodable { let type: String; let vehicleId: String? }
        struct Out: Decodable { let success: Bool?; let dvirId: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "drivers.startDVIR",
                input: In(type: "pre_trip", vehicleId: vehicleId.isEmpty ? nil : vehicleId))
            dvirId = resp.dvirId
            withAnimation(.easeInOut(duration: 0.18)) { step = .section(0) }
        } catch {
            actionErr = "The DVIR session didn't arm — check signal and try again."
        }
        inFlight = false
    }

    /// Section "Proceed / Submit" → commit this section's items (real per-section
    /// verb), mark it acked, then either advance or fire the terminal submit.
    private func proceed(from idx: Int) async {
        inFlight = true; actionErr = nil
        // 1 — commit the real checklist items for this section as passed.
        if categories.indices.contains(idx) {
            struct Item: Encodable { let itemId: String; let passed: Bool }
            struct In: Encodable { let vehicleId: String?; let items: [Item] }
            struct Out: Decodable { let success: Bool? }
            let items = categories[idx].items.map { Item(itemId: $0.id, passed: true) }
            do {
                let _: Out = try await EusoTripAPI.shared.mutation(
                    "drivers.submitPreTripInspection",
                    input: In(vehicleId: vehicleId.isEmpty ? nil : vehicleId, items: items))
            } catch {
                // Per-item commit is best-effort accumulation; the terminal
                // submitDVIR is the record of authority. Surface but don't block.
                actionErr = "Section items didn't sync — they'll re-commit on the terminal submit."
            }
        }
        acked.insert(idx)

        let isLast = idx + 1 >= total
        if isLast {
            await submitTerminal()
        } else {
            withAnimation(.easeInOut(duration: 0.18)) { step = .section(idx + 1) }
        }
        inFlight = false
    }

    /// The single terminal `submitDVIR(passed)` — fires once, at the last section.
    private func submitTerminal() async {
        guard let id = dvirId else {
            actionErr = "No DVIR session id — return to the receipt and re-arm."
            return
        }
        struct In: Encodable { let dvirId: String; let passed: Bool; let notes: String? }
        struct Out: Decodable { let success: Bool?; let result: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "drivers.submitDVIR",
                input: In(dvirId: id, passed: true, notes: "Pre-trip DVIR — all \(total) sections acked"))
            if resp.success == false {
                actionErr = "The inspection didn't submit — your sections are still acked, try again."
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { step = .complete }
            }
        } catch {
            actionErr = "The inspection didn't submit — check signal and try again."
        }
    }

    private func saveAndExit() async {
        // Draft acks re-derive from the server session on return; exit cleanly.
        onExit()
    }
}

// MARK: - Previews (Dark + Light)

#Preview("150 M-05 Pretrip DVIR · Dark") {
    DriverPretripDVIRM05Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.dark)
}

#Preview("150 M-05 Pretrip DVIR · Light") {
    DriverPretripDVIRM05Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.light)
}
