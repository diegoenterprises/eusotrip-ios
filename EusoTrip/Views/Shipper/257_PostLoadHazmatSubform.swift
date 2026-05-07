//
//  257_PostLoadHazmatSubform.swift
//  EusoTrip — Shipper · Post-a-Load · Hazmat sub-form.
//
//  UN # · class · packing group · proper shipping name · ERG · CHEMTREC.
//  Country-aware regulatory frame chips: 49 CFR (US) · NOM (MX) · ADR (EU)
//  · IMDG (vessel) · TDG (CA). Cross-border shows the trusted-trader
//  programs (CTPAT / FAST / OEA) the load may qualify for.
//

import SwiftUI

struct PostLoadHazmatSubformScreen: View {
    let theme: Theme.Palette
    @ObservedObject var draft: PostLoadDraft
    var body: some View {
        Shell(theme: theme) { HazmatBody(draft: draft) } nav: { shipperLifecycleNav() }
    }
}

private struct HazmatBody: View {
    @Environment(\.palette) private var palette
    @ObservedObject var draft: PostLoadDraft

    private let classes = ["1", "2.1", "2.2", "2.3", "3", "4.1", "4.2", "4.3", "5.1", "5.2", "6.1", "6.2", "7", "8", "9"]
    private let pgs = ["I", "II", "III"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                regulatoryChips
                idCard
                classificationCard
                psnCard
                ergCard
                chemtrecCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "triangle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                Text("SHIPPER · POST A LOAD · HAZMAT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(Brand.warning)
            }
            Text("Hazmat fields").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var regulatoryChips: some View {
        let frames = applicableFrames
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(frames, id: \.self) { frame in
                    Text(frame).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }
            }
        }
    }

    private var applicableFrames: [String] {
        var f: [String] = []
        if [PostLoadDraft.Country.US].contains(draft.originCountry) || [PostLoadDraft.Country.US].contains(draft.destinationCountry) {
            f.append("US 49 CFR 172/173/177")
        }
        if [PostLoadDraft.Country.CA].contains(draft.originCountry) || [PostLoadDraft.Country.CA].contains(draft.destinationCountry) {
            f.append("CA TDG")
        }
        if [PostLoadDraft.Country.MX].contains(draft.originCountry) || [PostLoadDraft.Country.MX].contains(draft.destinationCountry) {
            f.append("MX NOM-002-SCT")
        }
        if [PostLoadDraft.Country.EU, .UK].contains(draft.originCountry) || [PostLoadDraft.Country.EU, .UK].contains(draft.destinationCountry) {
            f.append("EU ADR")
        }
        if draft.mode == .vessel {
            f.append("IMDG")
        }
        if draft.mode == .rail {
            f.append("US 49 CFR 174 (rail)")
        }
        if draft.isUSMCA {
            f.append("USMCA · CTPAT-eligible")
        }
        return f
    }

    private var idCard: some View {
        LifecycleCard(accentWarning: true) {
            LifecycleSection(label: "UN NUMBER", icon: "number")
            TextField("e.g. UN1203", text: $draft.unNumber)
                .textFieldStyle(.plain).autocorrectionDisabled(true)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var classificationCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CLASS + PG", icon: "tag")
            Text("CLASS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(classes, id: \.self) { c in
                        Button { draft.hazmatClass = c } label: {
                            Text(c).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(draft.hazmatClass == c ? .white : palette.textPrimary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(draft.hazmatClass == c ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            Text("PACKING GROUP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary).padding(.top, 6)
            HStack(spacing: 6) {
                ForEach(pgs, id: \.self) { pg in
                    Button { draft.packingGroup = pg } label: {
                        Text(pg).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(draft.packingGroup == pg ? .white : palette.textPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(draft.packingGroup == pg ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var psnCard: some View {
        LifecycleCard {
            LifecycleSection(label: "PROPER SHIPPING NAME", icon: "doc.text")
            TextField("e.g. Gasoline", text: $draft.properShippingName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var ergCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ERG GUIDE #", icon: "book")
            TextField("e.g. 128", value: $draft.ergGuide, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var chemtrecCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CHEMTREC PHONE", icon: "phone")
            TextField("e.g. 1-800-424-9300", text: $draft.chemtrecPhone)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

#Preview("257 · Hazmat · Night") {
    PostLoadHazmatSubformScreen(theme: Theme.dark, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("257 · Hazmat · Afternoon") {
    PostLoadHazmatSubformScreen(theme: Theme.light, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
