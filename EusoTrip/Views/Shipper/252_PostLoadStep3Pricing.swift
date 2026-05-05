//
//  252_PostLoadStep3Pricing.swift
//  EusoTrip — Shipper · Post-a-Load · Step 3 PRICING.
//

import SwiftUI

struct PostLoadStep3PricingScreen: View {
    let theme: Theme.Palette
    @ObservedObject var draft: PostLoadDraft
    var body: some View {
        Shell(theme: theme) { PostLoadStep3Body(draft: draft) } nav: { shipperLifecycleNav() }
    }
}

private struct PostLoadStep3Body: View {
    @Environment(\.palette) private var palette
    @ObservedObject var draft: PostLoadDraft

    private let accessorialOptions = ["detention", "lumper", "layover", "TONU", "stop_charge", "wait_time"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                rateCard
                fuelCard
                accessorialsCard
                notesCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("POST A LOAD · STEP 3 · PRICING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text("Set the rate.")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.75)
        }
    }

    private var rateCard: some View {
        LifecycleCard {
            LifecycleSection(label: "TARGET RATE (USD)", icon: "tag")
            TextField("e.g. 1900", value: $draft.rate, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var fuelCard: some View {
        LifecycleCard {
            LifecycleSection(label: "FUEL SURCHARGE %", icon: "fuelpump")
            TextField("e.g. 18.5", value: $draft.fuelSurchargeRate, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var accessorialsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ACCESSORIALS ALLOWED", icon: "checklist")
            FlowList(items: accessorialOptions, selected: draft.accessorialsAllowed) { item in
                if let i = draft.accessorialsAllowed.firstIndex(of: item) {
                    draft.accessorialsAllowed.remove(at: i)
                } else {
                    draft.accessorialsAllowed.append(item)
                }
            }
        }
    }

    private var notesCard: some View {
        LifecycleCard {
            LifecycleSection(label: "NOTES TO CARRIER", icon: "text.alignleft")
            TextField("Special instructions, gate codes, etc.", text: $draft.notes, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "251"])
            } label: {
                Text("Back").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(palette.tintNeutral).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "253"])
            } label: {
                Text("Review").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }
}

private struct FlowList: View {
    @Environment(\.palette) private var palette
    let items: [String]
    let selected: [String]
    let onTap: (String) -> Void
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 96), spacing: 8)]
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button { onTap(item) } label: {
                    Text(item.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(on ? .white : palette.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }
}

#Preview("252 · Pricing · Night") {
    PostLoadStep3PricingScreen(theme: Theme.dark, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("252 · Pricing · Afternoon") {
    PostLoadStep3PricingScreen(theme: Theme.light, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
