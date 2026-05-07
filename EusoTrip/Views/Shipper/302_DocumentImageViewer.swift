//
//  302_DocumentImageViewer.swift
//  EusoTrip — Shipper · Image viewer (POD photos, BOL scans).
//

import SwiftUI

struct DocumentImageViewerScreen: View {
    let theme: Theme.Palette
    let imageUrl: String
    var body: some View {
        Shell(theme: theme) { ImageViewerBody(imageUrl: imageUrl) } nav: { shipperLifecycleNav() }
    }
}

private struct ImageViewerBody: View {
    @Environment(\.palette) private var palette
    let imageUrl: String
    @State private var scale: CGFloat = 1.0
    @State private var loading = true
    @State private var image: UIImage? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "photo").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · IMAGE VIEWER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            if let img = image {
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnificationGesture().onChanged { v in scale = max(1, min(4, v)) })
                    .frame(maxWidth: .infinity)
            } else if loading {
                LifecycleCard { Text("Loading image…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else {
                LifecycleCard { Text("Could not load image.").font(EType.caption).foregroundStyle(palette.textSecondary) }
            }
        }
        .padding(.horizontal, 14).padding(.top, 56)
        .task { await fetchImage() }
    }

    private func fetchImage() async {
        loading = true
        guard let url = URL(string: imageUrl) else { loading = false; return }
        if let (data, _) = try? await URLSession.shared.data(from: url),
           let img = UIImage(data: data) {
            image = img
        }
        loading = false
    }
}

#Preview("302 · Image viewer · Night") {
    DocumentImageViewerScreen(theme: Theme.dark, imageUrl: "").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("302 · Image viewer · Afternoon") {
    DocumentImageViewerScreen(theme: Theme.light, imageUrl: "").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
