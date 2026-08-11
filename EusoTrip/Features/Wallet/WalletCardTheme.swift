//
//  WalletCardTheme.swift
//  EusoTrip — the client model for a Wallet card style. Mirrors the server
//  registry (walletThemes.ts) and is normally REPLACED at runtime by the
//  server's `eusoWallet.listWalletThemes` so the two never drift. The baked
//  `.fallback` list is the offline/first-launch default.
//
//  TARGET: EusoTrip/Features/Wallet/WalletCardTheme.swift
//

import SwiftUI
import UIKit

struct WalletCardTheme: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let kind: String          // "solid" | "strip" | "background"
    let background: String    // "rgb(r,g,b)"
    let foreground: String
    let label: String
    var shipNow: Bool = true
    let manifestVersion: String?
    let revision: String?
    let digest: String?
    let passStyle: String
    let artSlot: String?
    let previewImageDataUrl: String?
    let logoImageDataUrl: String?

    // The server registry is the source of truth. Required fields decode
    // strictly so contract drift cannot create a fabricated theme.
    private enum CodingKeys: String, CodingKey {
        case id, name, kind, background, foreground, label, shipNow
        case manifestVersion, revision, digest, passStyle, artSlot
        case previewImageDataUrl, logoImageDataUrl
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(String.self, forKey: .id)
        name       = try c.decode(String.self, forKey: .name)
        kind       = try c.decode(String.self, forKey: .kind)
        background = try c.decode(String.self, forKey: .background)
        foreground = try c.decode(String.self, forKey: .foreground)
        label      = try c.decode(String.self, forKey: .label)
        shipNow    = try c.decodeIfPresent(Bool.self, forKey: .shipNow) ?? true
        manifestVersion = try c.decode(String.self, forKey: .manifestVersion)
        revision = try c.decode(String.self, forKey: .revision)
        digest = try c.decode(String.self, forKey: .digest)
        passStyle = try c.decode(String.self, forKey: .passStyle)
        artSlot = try c.decodeIfPresent(String.self, forKey: .artSlot)
        previewImageDataUrl = try c.decodeIfPresent(String.self, forKey: .previewImageDataUrl)
        logoImageDataUrl = try c.decode(String.self, forKey: .logoImageDataUrl)
    }

    /// The memberwise initializer the `.fallback` registry relies on (the
    /// custom `init(from:)` above suppresses Swift's synthesized one).
    init(id: String, name: String, kind: String,
         background: String, foreground: String, label: String,
         shipNow: Bool = true, manifestVersion: String? = nil,
         revision: String? = nil, digest: String? = nil,
         passStyle: String? = nil, artSlot: String? = nil,
         previewImageDataUrl: String? = nil,
         logoImageDataUrl: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.background = background
        self.foreground = foreground
        self.label = label
        self.shipNow = shipNow
        self.manifestVersion = manifestVersion
        self.revision = revision
        self.digest = digest
        self.passStyle = passStyle ?? (kind == "solid" ? "boardingPass" : "eventTicket")
        self.artSlot = artSlot ?? (kind == "solid" ? nil : kind)
        self.previewImageDataUrl = previewImageDataUrl
        self.logoImageDataUrl = logoImageDataUrl
    }

    var bg: Color  { Color(rgbString: background) }
    var ink: Color { Color(rgbString: foreground) }
    var accent: Color { Color(rgbString: label) }
    var isArt: Bool { kind != "solid" }
    var isVersioned: Bool {
        guard let revision, !revision.isEmpty, let digest, !digest.isEmpty else { return false }
        return true
    }
    var previewImage: UIImage? { WalletThemeImageCache.image(from: previewImageDataUrl, key: "preview:\(digest ?? id)") }
    var logoImage: UIImage? { WalletThemeImageCache.image(from: logoImageDataUrl, key: "logo:\(digest ?? id)") }
}

private enum WalletThemeImageCache {
    static let cache = NSCache<NSString, UIImage>()

    static func image(from dataUrl: String?, key: String) -> UIImage? {
        guard let dataUrl, !dataUrl.isEmpty else { return nil }
        let cacheKey = key as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        guard let comma = dataUrl.firstIndex(of: ","),
              dataUrl[..<comma].lowercased().contains(";base64"),
              let data = Data(base64Encoded: String(dataUrl[dataUrl.index(after: comma)...])),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}

extension WalletCardTheme {
    /// Baked mirror of walletThemes.ts — used until the server list loads.
    static let fallback: [WalletCardTheme] = [
        .init(id: "aurora-classic",   name: "Aurora Classic",    kind: "solid", background: "rgb(20,115,255)", foreground: "rgb(255,255,255)", label: "rgb(188,211,255)"),
        .init(id: "synthwave-sunset", name: "Synthwave Sunset",  kind: "background", background: "rgb(193,107,255)", foreground: "rgb(255,255,255)", label: "rgb(255,224,194)"),
        .init(id: "midnight-desert",  name: "Midnight Desert",   kind: "background", background: "rgb(42,29,82)",   foreground: "rgb(242,234,255)", label: "rgb(201,182,255)"),
        .init(id: "bluemagenta",      name: "Bluemagenta Bleed", kind: "background", background: "rgb(139,76,255)",  foreground: "rgb(255,255,255)", label: "rgb(255,255,255)"),
        .init(id: "frosted-glass",    name: "Frosted Glass",     kind: "background", background: "rgb(10,11,18)",   foreground: "rgb(255,255,255)", label: "rgb(158,197,255)"),
        .init(id: "flame-monolith",   name: "Flame Monolith",    kind: "solid", background: "rgb(255,255,255)", foreground: "rgb(21,21,28)",   label: "rgb(138,57,215)"),
        .init(id: "neon-grid",        name: "Neon Grid",         kind: "background", background: "rgb(26,15,58)",    foreground: "rgb(234,255,251)", label: "rgb(65,214,227)"),
        .init(id: "aurora-ribbon",    name: "Aurora Ribbon",     kind: "background", background: "rgb(10,10,15)",   foreground: "rgb(255,255,255)", label: "rgb(205,188,255)"),
        .init(id: "hazmat",           name: "HAZMAT",            kind: "background", background: "rgb(22,19,28)",   foreground: "rgb(255,255,255)", label: "rgb(255,200,61)"),
        .init(id: "carbon-tech",      name: "Carbon Tech",       kind: "solid", background: "rgb(20,21,26)",   foreground: "rgb(232,234,240)", label: "rgb(111,140,255)"),
        .init(id: "emerald-trail",    name: "Emerald Trail",     kind: "background", background: "rgb(15,110,86)",   foreground: "rgb(234,255,246)", label: "rgb(124,245,196)"),
        .init(id: "chrome-tanker",    name: "Chrome Tanker",     kind: "background", background: "rgb(208,211,220)", foreground: "rgb(22,22,28)",   label: "rgb(138,57,215)"),
        .init(id: "boarding-stub",    name: "Boarding Stub",     kind: "background", background: "rgb(74,58,160)",  foreground: "rgb(255,255,255)", label: "rgb(188,211,255)"),
        .init(id: "orb-hero",         name: "Orb Hero",          kind: "background", background: "rgb(7,7,12)",     foreground: "rgb(255,255,255)", label: "rgb(185,162,255)"),
        .init(id: "mono-minimal",     name: "Mono Minimal",      kind: "solid", background: "rgb(0,0,0)",      foreground: "rgb(255,255,255)", label: "rgb(207,198,255)"),
    ]
    static let defaultId = "aurora-classic"
}

extension Color {
    /// Parse "rgb(r,g,b)" → Color. Falls back to clear on a malformed string.
    init(rgbString s: String) {
        let nums = s.replacingOccurrences(of: "rgb(", with: "")
                    .replacingOccurrences(of: ")", with: "")
                    .split(separator: ",")
                    .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard nums.count == 3 else { self = .clear; return }
        self = Color(.sRGB, red: nums[0]/255, green: nums[1]/255, blue: nums[2]/255, opacity: 1)
    }
}
