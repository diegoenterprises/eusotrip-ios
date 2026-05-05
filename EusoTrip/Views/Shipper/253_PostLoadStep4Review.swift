//
//  253_PostLoadStep4Review.swift
//  EusoTrip — Shipper · Post-a-Load · Step 4 REVIEW.
//  Final wizard step. Renders the full draft summary and fires
//  `shippers.create` when the user taps Post.
//

import SwiftUI

struct PostLoadStep4ReviewScreen: View {
    let theme: Theme.Palette
    @ObservedObject var draft: PostLoadDraft
    var body: some View {
        Shell(theme: theme) { ReviewBody(draft: draft) } nav: { shipperLifecycleNav() }
    }
}

private struct ReviewBody: View {
    @Environment(\.palette) private var palette
    @ObservedObject var draft: PostLoadDraft

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                modeAndCountryCard
                laneCard
                equipmentCard
                pricingCard
                if draft.cargoType == .hazmat { hazmatCard }
                if draft.cargoType == .refrigerated { reeferCard }
                if !draft.stops.isEmpty { stopsCard }
                if let err = draft.postError { errorCard(err) }
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .onChange(of: draft.postedLoadNumber) { _, ln in
            if ln != nil {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "254"])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("POST A LOAD · STEP 4 · REVIEW")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text("Confirm and post.")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.75)
        }
    }

    private var modeAndCountryCard: some View {
        LifecycleCard {
            LifecycleSection(label: "MODE + LANE", icon: "globe.americas.fill")
            LifecycleRow(label: "Mode",        value: draft.mode.label)
            LifecycleRow(label: "Origin",      value: "\(draft.originCountry.flag) \(draft.originCountry.label)")
            LifecycleRow(label: "Destination", value: "\(draft.destinationCountry.flag) \(draft.destinationCountry.label)")
            if draft.isCrossBorder {
                Text(draft.isUSMCA ? "Cross-border · USMCA-eligible" : "Cross-border")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }
        }
    }

    private var laneCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LANE", icon: "map")
            LifecycleRow(label: "Origin",      value: dashIfEmpty(draft.origin))
            LifecycleRow(label: "Destination", value: dashIfEmpty(draft.destination))
            LifecycleRow(label: "Pickup",      value: draft.pickupDate.map(formatDate) ?? "—")
            LifecycleRow(label: "Delivery",    value: draft.deliveryDate.map(formatDate) ?? "—")
        }
    }

    private var equipmentCard: some View {
        LifecycleCard {
            LifecycleSection(label: "EQUIPMENT", icon: "shippingbox")
            LifecycleRow(label: "Cargo type",  value: draft.cargoType.label)
            LifecycleRow(label: "Equipment",   value: dashIfEmpty(draft.equipmentType))
            LifecycleRow(label: "Weight",      value: draft.weight.map { "\(Int($0)) lb" } ?? "—")
            LifecycleRow(label: "Commodity",   value: dashIfEmpty(draft.commodity))
        }
    }

    private var pricingCard: some View {
        LifecycleCard {
            LifecycleSection(label: "PRICING", icon: "dollarsign.circle")
            LifecycleRow(label: "Target rate", value: usd(draft.rate))
            LifecycleRow(label: "FSC %",       value: draft.fuelSurchargeRate.map { String(format: "%.1f%%", $0) } ?? "—")
            if !draft.accessorialsAllowed.isEmpty {
                LifecycleRow(label: "Accessorials", value: draft.accessorialsAllowed.joined(separator: ", "))
            }
            if !draft.notes.isEmpty {
                LifecycleRow(label: "Notes", value: draft.notes)
            }
        }
    }

    private var hazmatCard: some View {
        LifecycleCard(accentWarning: true) {
            LifecycleSection(label: "HAZMAT", icon: "triangle.fill")
            LifecycleRow(label: "UN",       value: dashIfEmpty(draft.unNumber))
            LifecycleRow(label: "Class",    value: dashIfEmpty(draft.hazmatClass))
            LifecycleRow(label: "PG",       value: dashIfEmpty(draft.packingGroup))
            LifecycleRow(label: "PSN",      value: dashIfEmpty(draft.properShippingName))
            LifecycleRow(label: "ERG",      value: draft.ergGuide.map { "#\($0)" } ?? "—")
            LifecycleRow(label: "CHEMTREC", value: dashIfEmpty(draft.chemtrecPhone))
            // Country-specific regulatory frames
            switch (draft.originCountry, draft.destinationCountry) {
            case (.US, _), (_, .US): LifecycleRow(label: "US 49 CFR", value: "Required")
            case (.MX, _), (_, .MX): LifecycleRow(label: "MX NOM",    value: "Required")
            case (.EU, _), (_, .EU): LifecycleRow(label: "EU ADR",    value: "Required")
            default: EmptyView()
            }
            if draft.mode == .vessel {
                LifecycleRow(label: "IMDG", value: "Required")
            }
        }
    }

    private var reeferCard: some View {
        LifecycleCard {
            LifecycleSection(label: "REEFER", icon: "thermometer")
            if let lo = draft.reeferTempLow, let hi = draft.reeferTempHigh {
                LifecycleRow(label: "Setpoint", value: "\(Int(lo))–\(Int(hi))°F")
            } else {
                LifecycleRow(label: "Setpoint", value: "—")
            }
            LifecycleRow(label: "Pre-cool", value: draft.preCoolRequired ? "Required" : "Not required")
            LifecycleRow(label: "Mode",     value: draft.continuousMode ? "Continuous" : "Cycle-sentry")
        }
    }

    private var stopsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "STOPS", icon: "list.number")
            ForEach(draft.stops) { stop in
                LifecycleRow(label: "\(stop.sequence). \(stop.address)", value: stop.appointmentISO ?? "—")
            }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
                Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
                Spacer(minLength: 0)
            }
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "252"])
            } label: {
                Text("Back").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(palette.tintNeutral).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Button {
                Task { await draft.submit() }
            } label: {
                HStack(spacing: 6) {
                    if draft.isPosting { ProgressView().tint(.white) }
                    Text(draft.isPosting ? "Posting…" : "Post load")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(draft.isPosting)
        }
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm"
        return f.string(from: d)
    }
}

#Preview("253 · Review · Night") {
    PostLoadStep4ReviewScreen(theme: Theme.dark, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("253 · Review · Afternoon") {
    PostLoadStep4ReviewScreen(theme: Theme.light, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
