//
//  269_InTransitException.swift
//  EusoTrip — Shipper · Stage 5 · IN TRANSIT · exception (refactored).
//

import SwiftUI

struct InTransitExceptionScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · IN TRANSIT · EXCEPTION · STAGE 5 OF 8", cycleStatus: "in_transit") { live in
                ExceptionBody(live: live, loadId: loadId)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct ExceptionBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    @State private var filing: Bool = false
    @State private var actionError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            statusCard
            timelineCard
            ctaRow
            if let err = actionError { errorBanner(err) }
        }
    }

    private var statusCard: some View {
        LifecycleCard(accentDanger: true) {
            LifecycleSection(label: "EXCEPTION", icon: "exclamationmark.triangle.fill")
            LifecycleRow(label: "Load status",  value: live.load.status.uppercased())
            if let g = live.lastGeofence {
                LifecycleRow(label: "Last event",  value: g.type.uppercased())
                LifecycleRow(label: "Recorded",    value: humanISO(g.eventTimestamp))
                if let dwell = g.dwellSeconds {
                    LifecycleRow(label: "Dwell", value: "\(dwell / 60) min")
                }
            }
            Text("Use the file-claim CTA to record an accessorial. Real claim builder lives at /freight-claims on the web; the iOS surface lands in 219 ShipperFreightClaims.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timelineCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LANE", icon: "map.fill")
            LifecycleRow(label: "Lane",     value: laneDisplay(live))
            LifecycleRow(label: "Pickup",   value: humanISO(live.pickup?.departedAt ?? live.pickup?.arrivedAt))
            LifecycleRow(label: "ETA",      value: humanISO(live.load.estimatedDeliveryDate))
            LifecycleRow(label: "Carrier",  value: dashIfEmpty(live.carrier?.name))
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "219", "loadId": loadId, "mode": "create"])
            } label: {
                Text("File claim").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Button {
                if let p = live.driver?.phone, let url = URL(string: "tel://\(p.filter(\.isNumber))") { UIApplication.shared.open(url) }
            } label: {
                Image(systemName: "phone.fill").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44).background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(live.driver?.phone?.isEmpty != false)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
                Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
                Spacer(minLength: 0)
            }
        }
    }
}

#Preview("269 · In transit · Exception · Night") {
    InTransitExceptionScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("269 · In transit · Exception · Afternoon") {
    InTransitExceptionScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
