//
//  381_RfpDetail.swift
//  EusoTrip — Shipper · RFP detail + lane awarding (Arc N).
//

import SwiftUI

struct RfpDetailScreen: View {
    let theme: Theme.Palette
    let rfpId: String
    var body: some View {
        Shell(theme: theme) { RfpDetailBody(rfpId: rfpId) } nav: { shipperLifecycleNav() }
    }
}

private struct RfpDetail: Decodable, Hashable {
    let id: String
    let title: String?
    let status: String?
    let dueDate: String?
    let lanes: [Lane]
    struct Lane: Decodable, Hashable, Identifiable {
        let id: String
        let origin: String?
        let destination: String?
        let mode: String?
        let bestBid: Double?
        let awardedCarrierName: String?
    }
}

private struct RfpDetailBody: View {
    @Environment(\.palette) private var palette
    let rfpId: String
    @State private var rfp: RfpDetail? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var awarding: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading RFP…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let r = rfp { summaryCard(r); lanesCard(r) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · RFP DETAIL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(rfp?.title ?? "—").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func summaryCard(_ r: RfpDetail) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "RFP", icon: "checkmark.seal")
            LifecycleRow(label: "Status",   value: dashIfEmpty(r.status?.uppercased()))
            LifecycleRow(label: "Due",      value: humanISO(r.dueDate))
            LifecycleRow(label: "Lanes",    value: "\(r.lanes.count)")
        }
    }

    private func lanesCard(_ r: RfpDetail) -> some View {
        VStack(spacing: 8) {
            ForEach(r.lanes) { lane in
                LifecycleCard {
                    LifecycleSection(label: "\(dashIfEmpty(lane.origin)) → \(dashIfEmpty(lane.destination))", icon: "arrow.right")
                    LifecycleRow(label: "Mode",     value: dashIfEmpty(lane.mode?.uppercased()))
                    LifecycleRow(label: "Best bid", value: usd(lane.bestBid))
                    LifecycleRow(label: "Awarded",  value: dashIfEmpty(lane.awardedCarrierName))
                    if lane.awardedCarrierName == nil {
                        Button { Task { await awardLane(lane.id) } } label: {
                            HStack {
                                if awarding == lane.id { ProgressView().tint(.white) }
                                Text(awarding == lane.id ? "Awarding…" : "Award lane")
                                    .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(LinearGradient.diagonal).clipShape(Capsule())
                        }.buttonStyle(.plain).disabled(awarding != nil)
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let rfpId: String }
        do {
            let r: RfpDetail = try await EusoTripAPI.shared.query("rfpManager.getRFPDetail", input: In(rfpId: rfpId))
            rfp = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func awardLane(_ laneId: String) async {
        awarding = laneId
        struct In: Encodable { let rfpId: String; let laneId: String }
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("rfpManager.awardLane", input: In(rfpId: rfpId, laneId: laneId))
            await load()
        } catch { /* surface inline */ }
        awarding = nil
    }
}

#Preview("381 · RFP detail · Night") { RfpDetailScreen(theme: Theme.dark, rfpId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("381 · RFP detail · Afternoon") { RfpDetailScreen(theme: Theme.light, rfpId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
