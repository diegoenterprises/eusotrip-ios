//
//  QRImageView.swift
//  EusoTrip — shared QR code renderer.
//
//  Lightweight SwiftUI wrapper around `CIQRCodeGenerator` (CoreImage)
//  with a CIColorInvert pass so the dark-mode background reads cleanly.
//  Used by Settings → Invite for the share-QR card, and ready for
//  EusoTicket / pickup-credential / wallet pass QR surfaces.
//
//  © Eusorone Technologies, Inc.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
#if canImport(UIKit)
import UIKit
#endif

struct QRImageView: View {
    /// The string to encode. URLs, deep links, short tokens — anything
    /// up to ~2.9KB will fit the standard QR alphanumeric capacity.
    let payload: String

    /// Render size. Defaults to 240pt — large enough for a phone-camera
    /// scan at conversational distance.
    var size: CGFloat = 240

    /// When true, draws a small EusoTrip glyph in the QR's center
    /// (using the QR `H` error-correction tier so the glyph doesn't
    /// destroy the encoded data).
    var withBrandGlyph: Bool = true

    var body: some View {
        ZStack {
            #if canImport(UIKit)
            if let image = render() {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                fallback
            }
            #else
            fallback
            #endif

            if withBrandGlyph {
                Circle()
                    .fill(.white)
                    .frame(width: size * 0.22, height: size * 0.22)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: size * 0.12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("QR code for \(payload)")
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.gray.opacity(0.15))
            .overlay(
                Text("QR\nunavailable")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 11, weight: .heavy))
            )
    }

    #if canImport(UIKit)
    private func render() -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        // Scale to target size — the raw CIImage is tiny by default.
        let scale = size / outputImage.extent.width
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    #endif
}

#Preview("QR · Dark") {
    QRImageView(payload: "https://app.eusotrip.com/register?ref=EUSO-DIEGO-AX7K&role=catalyst")
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("QR · Light") {
    QRImageView(payload: "https://app.eusotrip.com/register?ref=EUSO-DIEGO-AX7K&role=catalyst")
        .padding()
        .background(Color.white)
        .preferredColorScheme(.light)
}
