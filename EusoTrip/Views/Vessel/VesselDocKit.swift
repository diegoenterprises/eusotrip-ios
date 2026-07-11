//
//  VesselDocKit.swift
//  EusoTrip 2027 · 06 Vessel · Documentary-cluster shared kit (762–769)
//
//  Shared house primitives for the eight Vessel Operator documentation +
//  surcharge screens (762 Surcharge Transparency · 763 B/L Duplicate
//  Detection · 764 Reefer Plug Request · 765 Letter of Credit · 766 Letter
//  of Indemnity · 767 Sea Waybill · 768 Master & House B/L · 769 NVOCC FMC
//  Tariff & Bond). Factored out so all eight read as one designer's work:
//  the same sparkle eyebrow + booking-ref caption top bar, the same 9/800
//  section header, and the shared listBOLs decode shape.
//
//  REAL WIRING (documented here, not leaked into renderable copy):
//    · vesselShipments.listBOLs  {limit}  -> [bill_of_lading row]
//        (server/routers/vesselShipments.ts:961) — the live bills-of-lading
//        set for the signed-in operator; anchors every documentary hero.
//    · vesselShipments.getBOL    {id|bolNumber} -> row (:944)
//    · vesselShipments.createBOL {bolType:master|house|express|seaway} (:880)
//    · rateComparison.compare    {originPortId,destinationPortId,containerSize}
//        -> {rates:[{totalAllIn, surchargesBreakdown{baf,thcOrigin,
//        thcDestination,pss}}]} (server/routers/rateComparison.ts:17)
//
//  Analytic overlays flagged STUB in the wireframe <desc> (handed to
//  the-oath) are rendered from the certified representative model and are
//  labeled as such in each screen's header — never presented as live money.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - listBOLs decode row (shared across the documentary cluster)

/// One `billsOfLading` row as returned by `vesselShipments.listBOLs`.
/// MySQL hands decimals back as strings, so weight/volume are `String?`.
struct VesselDocBOL: Decodable, Identifiable {
    let id: Int
    let bolNumber: String?
    let bolType: String?
    let shipmentId: Int?
    let originPort: String?
    let destinationPort: String?
    let vesselName: String?
    let voyageNumber: String?
    let cargoDescription: String?
    let numberOfPackages: Int?
    let grossWeightKg: String?
    let status: String?
    let freightTerms: String?
    let shipperId: Int?
    let consigneeId: Int?
    let createdAt: String?

    /// Live lane string ("CNSHA → USLGB") when both ports are present.
    var lane: String? {
        guard let o = originPort, !o.isEmpty, let d = destinationPort, !d.isEmpty else { return nil }
        return "\(o) → \(d)"
    }

    /// Gross weight as a rounded kg integer when the string parses.
    var weightKg: Int? {
        guard let s = grossWeightKg, let v = Double(s), v > 0 else { return nil }
        return Int(v.rounded())
    }
}

// MARK: - Top bar (sparkle eyebrow + booking-ref caption + title + kebab)

/// The canonical Vessel documentary top bar. Mirrors the golden 731 cadence:
/// one ✦ eyebrow in the brand gradient, a right-aligned SF-Mono ID caption,
/// then the 28/700 title with a trailing kebab.
struct VesselDocTopBar: View {
    @Environment(\.palette) private var palette
    let eyebrow: String
    let idCaption: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text(eyebrow)
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                Text(idCaption)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Text(title)
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s4)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }
}

// MARK: - Section header (9/800 tracking label + optional right caption)

/// The house section eyebrow: `LABEL` in tertiary 9/800 tracked, with an
/// optional right-aligned human caption (a count, an ID, a status — never a
/// procedure name; wiring lives in the file header manifest).
struct VesselSectionHeader: View {
    @Environment(\.palette) private var palette
    let label: String
    var right: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 8)
            if let right {
                Text(right)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}

// MARK: - CTA pair (primary gradient + secondary outline)

/// The canonical bottom CTA pair used across the documentary cluster: a
/// wide primary gradient capsule (2:1) and a secondary outlined capsule.
struct VesselDocCTAPair: View {
    @Environment(\.palette) private var palette
    let primaryTitle: String
    let secondaryTitle: String
    var primaryIcon: String? = "arrow.right"
    var primaryDisabled: Bool = false
    var busy: Bool = false
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}

    var body: some View {
        HStack(spacing: Space.s3) {
            Button(action: { if !primaryDisabled && !busy { onPrimary() } }) {
                HStack(spacing: 7) {
                    if busy {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else if let primaryIcon {
                        Image(systemName: primaryIcon)
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(primaryTitle)
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    LinearGradient.primary.opacity(primaryDisabled ? 0.55 : 1.0)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(primaryDisabled || busy)

            Button(action: onSecondary) {
                Text(secondaryTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(minWidth: 128, minHeight: 48)
                    .padding(.horizontal, Space.s3)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Small honest states

/// Inline loading skeleton — a hero block + a body block, matching the
/// documentary cluster's hero-then-card rhythm.
struct VesselDocSkeleton: View {
    @Environment(\.palette) private var palette
    var bodyHeight: CGFloat = 300
    var body: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: bodyHeight)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }
}

/// A one-line honest note surfaced under a STUB-flagged section: states, in
/// plain user copy, that the figures shown are the reference model and the
/// live detector/allocator is pending — never dressed up as live data.
struct VesselDocGapNote: View {
    @Environment(\.palette) private var palette
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textTertiary)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Vessel Operator bottom nav (Home · Shipments* · orb · Compliance · Me)

extension BottomNav {
    /// The real Vessel Operator nav graph with SHIPMENTS current — used by
    /// every documentary screen in the cluster (all dock under Shipments).
    static func vesselOperatorShipments() -> BottomNav {
        BottomNav(
            leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                      NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
            trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                       NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
            orbState: .idle)
    }
}

// MARK: - Currency formatting

func vesselDocCurrency(_ v: Double, showCents: Bool = false) -> String {
    if !showCents && v == v.rounded() {
        return "$\(Int(v).formatted(.number.grouping(.automatic)))"
    }
    return "$\(String(format: "%.2f", v))"
}
