//
//  312_EsangAttachmentPicker.swift
//  EusoTrip — Shipper · ESang · Attachment picker (Arc I).
//

import SwiftUI

struct EsangAttachmentPickerScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { AttachmentPickerBody() } nav: { shipperLifecycleNav() }
    }
}

private struct AttachmentPickerBody: View {
    @Environment(\.palette) private var palette
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                grid
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("ESANG · ATTACH").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Attach to message").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var grid: some View {
        let cols = [GridItem(.adaptive(minimum: 100), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            tile(icon: "photo", label: "Photo", screen: "302")
            tile(icon: "doc", label: "Document", screen: "300")
            tile(icon: "shippingbox", label: "Load card", screen: "201")
            tile(icon: "mappin", label: "Location", screen: "256")
            tile(icon: "creditcard", label: "Settlement", screen: "292")
        }
    }

    private func tile(icon: String, label: String, screen: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": screen])
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(label).font(EType.caption).foregroundStyle(palette.textPrimary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }
}

#Preview("312 · Attach · Night") { EsangAttachmentPickerScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("312 · Attach · Afternoon") { EsangAttachmentPickerScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
