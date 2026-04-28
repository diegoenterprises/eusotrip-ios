//
//  362_CameraPermission.swift
//  EusoTrip — Shipper · Camera permission (Arc M).
//

import SwiftUI
import AVFoundation

struct CameraPermissionScreen: View {
    let theme: Theme.Palette
    var body: some View {
        PermissionRationaleScreen(
            theme: theme,
            title: "Camera",
            eyebrow: "Shipper · Camera",
            icon: "camera.fill",
            message: "Camera access lets you capture POD photos, scan BOLs, and attach evidence to freight claims directly from the dock.",
            bullets: [
                "POD photo capture with on-device OCR",
                "Scan BOL barcodes / QR codes",
                "Attach photo evidence to freight claims",
                "Photos stay on-device until you upload",
            ],
            onGrant: {
                AVCaptureDevice.requestAccess(for: .video) { _ in }
            }
        )
    }
}

#Preview("362 · Camera · Night") { CameraPermissionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("362 · Camera · Afternoon") { CameraPermissionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
