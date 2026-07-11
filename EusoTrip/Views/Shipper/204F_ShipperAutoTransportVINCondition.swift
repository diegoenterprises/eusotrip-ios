//
//  204F_ShipperAutoTransportVINCondition.swift
//  EusoTrip 2027 — Shipper · Auto-Transport VIN & Condition (brick 204F).
//
//  ARCHETYPE: CAPTURE / DAMAGE-DIAGRAM. A side-profile vehicle silhouette
//  with numbered pre-existing-damage markers + the VIN/photo tally leads,
//  a per-unit VEHICLE MANIFEST grid follows, closing on a SECUREMENT &
//  CONDITION 2×2. Purpose-built for photo-evidence damage defense.
//
//  Persona §11: Diego Usoro / Eusorone Technologies. Featured load:
//  LD-260614-AT5V9 · 7 vehicles · open carrier · Detroit MI → Dallas TX ·
//  1 pre-existing-damage unit.
//
//  ── WIRING MANIFEST (endpoint · file:line · state) ────────────────────
//  Web parity: shipper/loads/[id]/auto-condition.tsx
//  LIVE  trailerRegulatory.getAutoCarrierRegulations  trailerRegulatory.ts:504
//        — 49 CFR 393.128 securement + VIN-verification rule text.
//  LIVE  loads.getById                          loads.ts:1152
//  STUB  documents.attachConditionPhotos — named gap. Proposed:
//        documents.attachConditionPhotos({loadId, unit, photos[8]})
//          → writes condition doc rows + blockchainAuditTrail (immutable
//        pre/post baseline), broadcasts WS_EVENTS.CONDITION_CAPTURED. CTA.
//  STUB  vin.decodeAndVerify — named gap. Proposed:
//        vin.decodeAndVerify({vin}) → NHTSA decode cross-checked vs BOL.
//  transportMode TRUCK · country US (49 CFR 393.128). Degraded →
//  "VIN decode pending (degraded)".
//

import SwiftUI

// MARK: - Model

private struct AutoUnit: Identifiable {
    enum Status { case clean, damage }
    let id = UUID()
    let position: Int
    let make: String
    let badge: String?          // e.g. "EV"
    let vinLine: String
    let status: Status
}

private struct SecureCell: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let tint: Color
}

private struct AutoModel {
    var carrierLine: String
    var laneMono: String
    var vinsVerified: String
    var photos: String
    var preExisting: String
    var damageCaption: String
    var units: [AutoUnit]
    var secure: [SecureCell]

    static let canonical = AutoModel(
        carrierLine: "Open carrier · 7 units",
        laneMono: "DET MI → DAL TX · 8-photo set",
        vinsVerified: "7 / 7",
        photos: "56 / 56",
        preExisting: "1 unit",
        damageCaption: "Unit #4 · BMW X5 · 2 marks",
        units: [
            AutoUnit(position: 1, make: "Tesla Model Y", badge: "EV",
                     vinLine: "VIN …A41F22 · 8/8 photos", status: .clean),
            AutoUnit(position: 2, make: "Ford F-150", badge: nil,
                     vinLine: "VIN …B73K88 · 8/8 photos", status: .clean),
            AutoUnit(position: 3, make: "Honda CR-V", badge: nil,
                     vinLine: "VIN …C19M07 · 8/8 photos", status: .clean),
            AutoUnit(position: 4, make: "BMW X5", badge: nil,
                     vinLine: "VIN …D55P31 · 8/8 · L-door + bumper", status: .damage),
        ],
        secure: [
            SecureCell(icon: "checkmark", title: "2 tiedowns / unit",
                       detail: "393.128(a) · all 7", tint: Brand.success),
            SecureCell(icon: "checkmark", title: "Parking brake set",
                       detail: "all units · in Park", tint: Brand.success),
            SecureCell(icon: "checkmark", title: "Drip pans placed",
                       detail: "under all units", tint: Brand.success),
            SecureCell(icon: "bolt.fill", title: "EV state of charge",
                       detail: "64% · within 20–80%", tint: Brand.info),
        ]
    )
}

// MARK: - Store

@MainActor
private final class AutoStore: ObservableObject {
    @Published private(set) var model = AutoModel.canonical
    @Published private(set) var degraded: String? = nil
    @Published var capturing = false

    let loadId: String
    private let api: EusoTripAPI

    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    func refresh() async {
        struct In: Encodable { let trailerType: String }
        struct Reg: Decodable { let trailerType: String? }
        do {
            let _: Reg = try await api.query(
                "trailerRegulatory.getAutoCarrierRegulations",
                input: In(trailerType: "auto_carrier"))
            degraded = nil
        } catch {
            degraded = "VIN decode pending (degraded) — showing last capture"
        }
    }

    func capture() async {
        capturing = true
        defer { capturing = false }
        struct In: Encodable { let loadId: String }
        let _: AutoAck? = try? await api.mutation(
            "documents.attachConditionPhotos", input: In(loadId: loadId))
    }
}

private struct AutoAck: Decodable {}

// MARK: - View

struct ShipperAutoTransportVINCondition: View {
    let loadId: String
    @StateObject private var store: AutoStore
    @Environment(\.palette) private var palette

    init(loadId: String = "LD-260614-AT5V9") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: AutoStore(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(eyebrow: "✦ SHIPPER · AUTO-TRANSPORT",
                              idText: store.loadId,
                              title: "Auto carrier · 7")

                if let degraded = store.degraded {
                    DegradedNote(text: degraded).padding(.top, Space.s3)
                }

                captureHero
                    .padding(.horizontal, Space.s5).padding(.top, Space.s4)

                SectionLabel("VEHICLE MANIFEST · 49 CFR 393.128 · 7 UNITS")
                    .padding(.top, Space.s5)
                manifest
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                SectionLabel("SECUREMENT & CONDITION · 49 CFR 393.128")
                    .padding(.top, Space.s5)
                secureGrid
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                AddendaCTAPair(primary: "Capture condition",
                               secondary: "Verify VINs",
                               primaryLoading: store.capturing,
                               onPrimary: { Task { await store.capture() } },
                               onSecondary: {
                                   NotificationCenter.default.post(
                                       name: .eusoShippereSangTapped, object: nil)
                               })
                    .padding(.top, Space.s5)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: Capture hero

    private var captureHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("VEHICLE CONDITION · 7 UNITS · 1 PRE-EXISTING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Brand.info)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Brand.info.opacity(0.12))

            HStack(alignment: .top, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .topLeading) {
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 60, weight: .regular))
                            .foregroundStyle(Brand.info.opacity(0.85))
                        damageBadge(1).offset(x: 40, y: 8)
                        damageBadge(2).offset(x: 78, y: 4)
                    }
                    .frame(width: 132, height: 66, alignment: .leading)
                    Text(store.model.damageCaption)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(store.model.carrierLine)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(store.model.laneMono)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                    Divider().overlay(palette.borderFaint).padding(.vertical, 2)
                    tallyRow("VINS VERIFIED", store.model.vinsVerified, Brand.success)
                    tallyRow("CONDITION PHOTOS", store.model.photos, palette.textPrimary)
                    tallyRow("PRE-EXISTING DAMAGE", store.model.preExisting, Brand.hazmat)
                }
            }
            .padding(Space.s4)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .addendaPanel(palette)
    }

    private func damageBadge(_ n: Int) -> some View {
        Circle().fill(Brand.warning).frame(width: 18, height: 18)
            .overlay(Text("\(n)").font(.system(size: 11, weight: .heavy)).foregroundStyle(.black))
    }

    private func tallyRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: Space.s2)
            Text(value)
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                .foregroundStyle(color)
        }
    }

    // MARK: Vehicle manifest

    private var manifest: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.model.units.enumerated()), id: \.element.id) { idx, unit in
                HStack(spacing: Space.s3) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(unit.status == .damage ? Brand.warning.opacity(0.20) : Brand.info.opacity(0.16))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text("\(unit.position)")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(unit.status == .damage ? Brand.hazmat : Brand.info))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(unit.make)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                            if let badge = unit.badge {
                                Text(badge)
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(Brand.info)
                            }
                        }
                        Text(unit.vinLine)
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: Space.s2)
                    AddendaChip(text: unit.status == .damage ? "DAMAGE" : "CLEAN",
                                color: unit.status == .damage ? Brand.warning : Brand.success)
                }
                .padding(Space.s4)
                if idx < store.model.units.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, Space.s4)
                }
            }
        }
        .addendaPanel(palette)
    }

    // MARK: Securement 2×2

    private var secureGrid: some View {
        let cols = [GridItem(.flexible(), spacing: Space.s2),
                    GridItem(.flexible(), spacing: Space.s2)]
        return LazyVGrid(columns: cols, spacing: Space.s2) {
            ForEach(store.model.secure) { cell in
                HStack(spacing: Space.s2) {
                    Image(systemName: cell.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(cell.tint).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cell.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text(cell.detail)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(cell.tint)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .addendaPanel(palette, radius: Radius.md)
            }
        }
    }
}

// MARK: - Previews

#Preview("204F · Auto-Transport VIN & Condition · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperAutoTransportVINCondition()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("204F · Auto-Transport VIN & Condition · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperAutoTransportVINCondition()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
