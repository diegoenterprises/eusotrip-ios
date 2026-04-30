//
//  403_BrokerTenderToCarrier.swift
//  EusoTrip — Broker · Tender to carrier (book the load).
//
//  Cross-role chain: broker offers tender → carrier sees on
//  catalysts.getMyAwardedLoads (load.brokerId is now set + status
//  flips assigned) → driver hydrates trip → shipper.getLifecycleSnapshot
//  shows carrier + broker + driver populated.
//

import SwiftUI

struct BrokerTenderToCarrierScreen: View {
    let theme: Theme.Palette
    let loadId: String
    let catalystId: String
    var body: some View {
        Shell(theme: theme) { TenderBody(loadId: loadId, catalystId: catalystId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Carriers", systemImage: "person.3.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct TenderBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    let catalystId: String
    @State private var carrierRate: Double? = nil
    @State private var commission: Double? = nil
    @State private var pickupBy: Date = Date().addingTimeInterval(86400)
    @State private var sending = false
    @State private var sent = false
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { LifecycleCard(accentGradient: true) { Text("Tendered. Carrier notified, agreement queued.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                rateCard
                commissionCard
                pickupCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("BROKER · TENDER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Tender to carrier").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var rateCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CARRIER PAY (USD)", icon: "dollarsign.circle")
            TextField("e.g. 1700", value: $carrierRate, format: .number).keyboardType(.decimalPad).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var commissionCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "MARGIN (BROKER COMMISSION)", icon: "chart.line.uptrend.xyaxis")
            TextField("e.g. 200", value: $commission, format: .number).keyboardType(.decimalPad).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var pickupCard: some View {
        LifecycleCard {
            LifecycleSection(label: "PICKUP BY", icon: "calendar")
            DatePicker("", selection: $pickupBy, displayedComponents: [.date, .hourAndMinute]).labelsHidden()
        }
    }

    private var ctaRow: some View {
        Button { Task { await tender() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Tendering…" : "Send tender").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending || carrierRate == nil)
    }

    private func tender() async {
        sending = true; actionError = nil
        struct In: Encodable { let loadId: String; let catalystId: String; let carrierRate: Double; let commission: Double?; let pickupByISO: String }
        struct Out: Decodable { let success: Bool; let agreementId: String? }
        let f = ISO8601DateFormatter()
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation(
                "brokers.tenderToCarrier",
                input: In(loadId: loadId, catalystId: catalystId, carrierRate: carrierRate ?? 0, commission: commission, pickupByISO: f.string(from: pickupBy))
            )
            sent = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("403 · Tender · Night") { BrokerTenderToCarrierScreen(theme: Theme.dark, loadId: "1", catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("403 · Tender · Afternoon") { BrokerTenderToCarrierScreen(theme: Theme.light, loadId: "1", catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
