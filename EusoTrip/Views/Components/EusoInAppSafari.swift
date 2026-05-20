//
//  EusoInAppSafari.swift
//  EusoTrip — Canonical in-app web view (SFSafariViewController).
//
//  Founder doctrine "all on the app": every web link the iOS app
//  opens stays inside the EusoTrip process via SFSafariViewController
//  rather than bouncing the user to the system Safari app. Cookies +
//  paywall sessions + form fills survive the round-trip exactly as
//  if Safari opened them — the SFSafariViewController instance is
//  effectively a chromeless WebKit + Safari's saved-credentials store.
//
//  Usage from any SwiftUI surface:
//
//      @State private var inAppLink: EusoSafariLink? = nil
//
//      Button("Open audit trail") {
//          if let u = URL(string: "https://app.eusotrip.com/...") {
//              inAppLink = EusoSafariLink(url: u)
//          }
//      }
//      .sheet(item: $inAppLink) { link in
//          EusoInAppSafari(url: link.url).ignoresSafeArea()
//      }
//
//  Brand-tinted (magenta control accent) so the in-app browser reads
//  as part of EusoTrip, not a generic Safari sheet.
//

import SwiftUI
import SafariServices
import UIKit

/// Identifiable URL wrapper for `.sheet(item:)` presentation. The
/// UUID id forces a fresh sheet on every tap so navigating to two
/// different URLs back-to-back re-presents instead of deduping.
struct EusoSafariLink: Identifiable, Hashable {
    let id: UUID
    let url: URL

    init(url: URL) {
        self.id = UUID()
        self.url = url
    }
}

struct EusoInAppSafari: UIViewControllerRepresentable {
    let url: URL
    var enterReaderIfAvailable: Bool = false

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let cfg = SFSafariViewController.Configuration()
        cfg.entersReaderIfAvailable = enterReaderIfAvailable
        cfg.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: cfg)
        vc.dismissButtonStyle = .done
        // Brand magenta — matches LinearGradient.diagonal's terminal stop.
        vc.preferredControlTintColor = UIColor(red: 0.745, green: 0.004, blue: 1.0, alpha: 1)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
