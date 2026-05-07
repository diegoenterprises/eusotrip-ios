//
//  258_PostLoadReeferSubform.swift
//  EusoTrip — Shipper · Post-a-Load · Reefer sub-form.
//

import SwiftUI

struct PostLoadReeferSubformScreen: View {
    let theme: Theme.Palette
    @ObservedObject var draft: PostLoadDraft
    var body: some View {
        Shell(theme: theme) { ReeferSubformBody(draft: draft) } nav: { shipperLifecycleNav() }
    }
}

private struct ReeferSubformBody: View {
    @Environment(\.palette) private var palette
    @ObservedObject var draft: PostLoadDraft

    private let presets: [(label: String, lo: Double, hi: Double)] = [
        ("Frozen (-10 to 0°F)", -10, 0),
        ("Frozen (0 to 10°F)", 0, 10),
        ("Cold (28 to 36°F)", 28, 36),
        ("Fresh (33 to 38°F)", 33, 38),
        ("Pharma (35 to 46°F)", 35, 46),
        ("Floral (40 to 50°F)", 40, 50),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                presetsCard
                customCard
                modeCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "thermometer").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · POST A LOAD · REEFER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Reefer setpoint").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var presetsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "PRESETS", icon: "list.bullet")
            ForEach(presets, id: \.label) { preset in
                Button {
                    draft.reeferTempLow = preset.lo
                    draft.reeferTempHigh = preset.hi
                } label: {
                    HStack {
                        Image(systemName: matches(preset) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(matches(preset) ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                        Text(preset.label).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }.buttonStyle(.plain)
            }
        }
    }

    private func matches(_ p: (label: String, lo: Double, hi: Double)) -> Bool {
        draft.reeferTempLow == p.lo && draft.reeferTempHigh == p.hi
    }

    private var customCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CUSTOM RANGE", icon: "slider.horizontal.3")
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LOW (°F)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    TextField("e.g. 33", value: $draft.reeferTempLow, format: .number)
                        .keyboardType(.numberPad).textFieldStyle(.plain)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(palette.bgCard.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("HIGH (°F)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    TextField("e.g. 38", value: $draft.reeferTempHigh, format: .number)
                        .keyboardType(.numberPad).textFieldStyle(.plain)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(palette.bgCard.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var modeCard: some View {
        LifecycleCard {
            LifecycleSection(label: "OPERATION", icon: "fan")
            Toggle(isOn: $draft.preCoolRequired) {
                Text("Pre-cool required at pickup").font(EType.body).foregroundStyle(palette.textPrimary)
            }
            Toggle(isOn: $draft.continuousMode) {
                Text("Continuous mode (vs cycle-sentry)").font(EType.body).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var ctaRow: some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "251"])
        } label: {
            Text("Done").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }
}

#Preview("258 · Reefer · Night") {
    PostLoadReeferSubformScreen(theme: Theme.dark, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("258 · Reefer · Afternoon") {
    PostLoadReeferSubformScreen(theme: Theme.light, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
