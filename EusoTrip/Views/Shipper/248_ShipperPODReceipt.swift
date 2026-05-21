//
//  248_ShipperPODReceipt.swift
//  EusoTrip — Shipper · POD Receipt (brick 248).
//
//  Pixel-match to `02 Shipper/Dark-SVG/248 Shipper POD Receipt.svg`.
//  Shipper's view at POD-receipt moment — 72/72 reconciled, 36°F seal
//  final, ME signed, TR signed, DU tap-ready for NET-30 arm-on-tap.
//
//  Wire bindings:
//    loads.getById(loadId)         — load context
//    podCapture.getForLoad(loadId) — POD record + reefer overlay + seal
//

import SwiftUI

private struct PODLoad: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let cargoType: String?
    let palletCount: Int?
    let actualDeliveryDate: String?
    let carrierName: String?
}

private struct PODRecord: Decodable, Hashable {
    let loadId: Int?
    let palletsReceived: Int?
    let palletsExpected: Int?
    let sealNumber: String?
    let temperatureF: Double?
    let signedByDriver: Bool?
    let signedByReceiver: Bool?
    let signedByShipper: Bool?
    let driverSignedAt: String?
    let receiverSignedAt: String?
    let queuedAt: String?
    let payableStatus: String?
}

struct ShipperPODReceiptScreen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) { PODBody(loadId: loadId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Post",  systemImage: "plus.rectangle",   isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true),
                           NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct PODBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: PODLoad?
    @State private var pod: PODRecord?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && pod == nil {
                    LifecycleCard { Text("Loading POD…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    contextBanner
                    signersBlock
                    kpiGrid
                    armOnTapCTA
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · LOADS · POD RECEIPT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("POD receipt · ready").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            let pal = pod?.palletsReceived ?? 0
            let exp = pod?.palletsExpected ?? 0
            let temp = pod?.temperatureF.map { String(format: "%.0f°F", $0) } ?? "—"
            Text("\(pal)/\(exp) RECONCILED · \(temp) SEAL-FINAL · QUEUED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var contextBanner: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("§272 DISPATCHED · §292 ME SIGNED · NET-30 ARM-ON-TAP")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                if let l = load {
                    Text("\(l.loadNumber ?? "LD-\(l.id ?? 0)") · ePOD CERT QUEUED · ready for shipper sign-off")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private var signersBlock: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("SIGNATURE CHAIN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                signerRow("ME", "Driver", pod?.signedByDriver, pod?.driverSignedAt)
                signerRow("TR", "Receiver", pod?.signedByReceiver, pod?.receiverSignedAt)
                signerRow("DU", "Shipper (you)", pod?.signedByShipper, nil)
            }
        }
    }

    private func signerRow(_ axis: String, _ role: String, _ signed: Bool?, _ at: String?) -> some View {
        HStack {
            Text(axis)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(palette.bgCardSoft))
                .foregroundStyle(palette.textTertiary)
            Text(role).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            if signed == true {
                if let iso = at, !iso.isEmpty {
                    Text("signed \(timeAgo(iso))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("SIGNED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                        .foregroundStyle(.green)
                }
            } else {
                Text("TAP-READY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var kpiGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        let pal = pod?.palletsReceived ?? 0
        let exp = pod?.palletsExpected ?? 0
        return LazyVGrid(columns: cols, spacing: 8) {
            kpi("PALLETS", "\(pal)/\(exp)", "RECEIVED · seal", .green)
            kpi("POD CERT", "QUEUED", "awaiting DU", .orange)
            kpi("TEMP", pod?.temperatureF.map { String(format: "%.0f°F", $0) } ?? "—", "SEAL · final", .blue)
            kpi("PAYABLE", (pod?.payableStatus ?? "ARM-ON-TAP").uppercased(), "NET-30", .green)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    private var armOnTapCTA: some View {
        Button { } label: {
            HStack(spacing: 8) {
                Image(systemName: "signature").font(.system(size: 13, weight: .bold))
                Text("Sign POD · arm NET-30")
                    .font(EType.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func timeAgo(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return iso }
        let mins = max(0, Int(Date().timeIntervalSince(d) / 60))
        if mins < 1 { return "0:01" }
        return "0:\(String(format: "%02d", mins))"
    }

    private func loadAll() async {
        loading = true; defer { loading = false }
        async let l: Void = loadCtx()
        async let p: Void = loadPOD()
        _ = await (l, p)
    }
    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
    private func loadPOD() async {
        struct In: Encodable { let loadId: String }
        do { pod = try await EusoTripAPI.shared.query("podCapture.getForLoad", input: In(loadId: loadId)) } catch { /* */ }
    }
}

#Preview("248 · Dark")  { ShipperPODReceiptScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("248 · Light") { ShipperPODReceiptScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
