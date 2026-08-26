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
        // The existing signer renders non-solid pickup designs in the
        // event-ticket strip slot. Keep the baked catalog aligned with that
        // real PassKit surface; the live catalog remains authoritative.
        self.artSlot = artSlot ?? (kind == "solid" ? nil : "strip")
        self.previewImageDataUrl = previewImageDataUrl
        self.logoImageDataUrl = logoImageDataUrl
    }

    var bg: Color  { Color(rgbString: background) }
    var ink: Color { Color(rgbString: foreground) }
    var accent: Color { Color(rgbString: label) }
    var isArt: Bool { kind != "solid" }
    var normalizedArtSlot: String? {
        let value = artSlot?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return value.isEmpty ? nil : value
    }
    var expectedPassArtworkSHA256: [String]? {
        WalletPassArtworkCatalog.sha256ByTheme[id]
    }
    var isVersioned: Bool {
        guard let manifestVersion, !manifestVersion.isEmpty,
              let revision, !revision.isEmpty,
              let digest, !digest.isEmpty,
              ["solid", "strip", "background"].contains(kind)
        else { return false }

        if kind == "solid" {
            return passStyle == "boardingPass" && normalizedArtSlot == nil
        }
        return passStyle == "eventTicket"
            && normalizedArtSlot == "strip"
            && expectedPassArtworkSHA256?.count == 3
    }
    var previewImage: UIImage? {
        // Art themes preview the exact Apple Wallet strip adaptation bundled
        // from the original 15-design package. The taller source artwork is a
        // design reference, not the image PassKit renders on an event ticket.
        (normalizedArtSlot == "strip" ? UIImage(named: "wallet-strip-\(id)") : nil)
            ?? WalletThemeImageCache.image(from: previewImageDataUrl, key: "preview:\(digest ?? id)")
            ?? UIImage(named: id)
    }
    var logoImage: UIImage? { WalletThemeImageCache.image(from: logoImageDataUrl, key: "logo:\(digest ?? id)") }
}

/// SHA-256 fingerprints for the original, already-approved Apple Wallet strip
/// adaptations at 1x, 2x, and 3x. A signed pass must contain these exact bytes
/// for its selected design before the native add sheet can be shown.
enum WalletPassArtworkCatalog {
    static let sha256ByTheme: [String: [String]] = [
        "aurora-classic": ["db1ce41be965aa49d5418a68fb5b1dae98291175303575288c6c3e973005bc11", "6ae51c36a7b7373af6b55c4ccb2f0d26d286a3d553580c6662e0a69a2323294c", "5bcd5c7180f457e0ad96f5ff86578cfeb83aefca2064b9890a841a2559ba2dbd"],
        "synthwave-sunset": ["440b6a1b80fac84a6f4b01e254b65c8cad74248edea9bb2cb08f7ee0ae68b647", "7e0c823fb66f57dd0531a23dbe18cc4763462014c291a9cec89db9a665769f2a", "86ce723de8f378b331aa2c7e005375cefd57b75bd29fa40564aaa09680dd1c02"],
        "midnight-desert": ["f446a048f803b47c0fa4cc618bcf7de5e69d9882ed6a584f5dda9ba8b4425318", "2a8da3b896634cabdb5db10bada8149dda9698530460c1e1e4470979f3eb2208", "a2529318e904254e509f6904e1fb8ddacc442749f89371685538bb713fb84b5f"],
        "bluemagenta": ["bdaaecdef4bc73b59bd52b47513e1dd0ded3a985f6c4b99406e857ba69013d86", "17944a2dd14d972f13871bafee35a2a95157a498c080b34d39503ee1f52d3d3f", "0f24024d8bb1b9134fbfb86170c613d54d033c0944c2a241a89261c6a0f893af"],
        "frosted-glass": ["8b222601113449997113c81af7cb4ae29d5166ed3de8344ab72fc369c4a3082b", "53680da7a6656130e121ce8a26bdf6b221c75f032c3068fdea1731062f9bd277", "90313004fbf13072e2e3b4b84ab2d5e4cf192608239498ce3333ebea351c188a"],
        "flame-monolith": ["4c1a348bc7088164d764be90295d00e2aa6e75af4b2c927acacea5867da6031e", "91f7f49937e59bfb26dbbba40538522b585dad25857460cef4c49326ef99b30c", "fcf5f450a584c3bbea9ac0704ec10ef1f28130e32f289e4d4b6204378f85bff0"],
        "neon-grid": ["5536f5317d1812617f34c6c55768e19bfb91e5b2ad0eecf8189c12cd2e708e0b", "6f034c2269855443f9f4005394052a5aa690c530f7a2e5247eaaf8c3c71a4e8c", "8d77e18b7af14a1393daebc4aaf139494754e1b555c831c3fff9f991511f2e65"],
        "aurora-ribbon": ["271d420dd25ac20cb4aa46b03f55660dddb605b54c25e3a2b8c9b190da444aff", "2f55cd8820c8741175c26a584da81f4e84a828675b029915d93adcaade35c2e5", "001d3a955710e673169a3c0df2574dbfc022bd97d1b3af27aaf54b6417a87d98"],
        "hazmat": ["097d74f4e5250cde75750ddd40a8e42820113848639ab83c2f3b3df8b584e227", "20ed92882ce5dc4c6081c5ad371476a262ceac3d3414a3a5812595bdadc3238f", "70ef0e01512fe92d29e0f0f8400fef748b20f6dfdb720d86516f5dcd0a8b7771"],
        "carbon-tech": ["060116dec244e3c632ddb58dfeaa14c174f2696c5754009735eaf6cf99b411d8", "e58497e6a8ae4400e7534e790becb50a466569ba65aeb19d7959435a3ed99f30", "1288b49fd4caeda6062ffccaff74df6baefa29f969b1377a70b44f5a9ce0f278"],
        "emerald-trail": ["e7bb8fa5bc362bcce476d56198db78792bf99d6e63012ed9cde96ba0dfc3a462", "de72f9aa45672d231784482ddf21d8182301e92608794892dc8f865ad2ca7dca", "ad6b429cfdc83f488ad4a21ddc9721fa2386ce7f03779b67f79119e2085257cf"],
        "chrome-tanker": ["2610b6a72c3fc30386a2f70400335011cf31930ada7c38224c504fa613d2328d", "613581fb978960a0ea276667c96a691a41c92b1d7619a6c38860f7c956a34146", "eb14ec0ad26b4109c74cd08db82faef716c99f8f16e7ec74409a386e65064d25"],
        "boarding-stub": ["a836dbe667c19f69e848b918df9a3d56f03331aacb83e258ce177cb71c493b15", "729d16150012219d6d4ecfd66a573785ea1189a9ae9de7a8f94e7b2b4b2e5684", "53bd4bc1dffe7e3199b906d536bebb36c14db9c36973c1087733c9ed4548d663"],
        "orb-hero": ["bd3373e3b1aefb16f427bc4efec726b956f4040934e77a0d9354a6756927a272", "2611e6872603b67144398c6b21342ba6ea014cb301f903da36f616fbf3f72a6e", "e68ec8bc731dda3fb25a58d7e119a1cee2d6fc92a04afc5066c7e6f7eeffb4b6"],
        "mono-minimal": ["202c3ddba93b28ce2f048dea310fa56d7138f171ba51d0a54021dac059d25192", "4efcfb10f667b4c67fea5f97fb9690c825714dccc0851309b7578d01183b42dc", "7de0e11e0b6d63e35adde773fa9b5fc16f7ad14c0aaf44d4c7103a290030f6c0"],
    ]
}

private enum WalletThemeImageCache {
    static let cache = NSCache<NSString, UIImage>()

    static func data(from dataUrl: String?) -> Data? {
        guard let dataUrl, !dataUrl.isEmpty,
              let comma = dataUrl.firstIndex(of: ","),
              dataUrl[..<comma].lowercased().contains(";base64") else { return nil }
        return Data(base64Encoded: String(dataUrl[dataUrl.index(after: comma)...]))
    }

    static func image(from dataUrl: String?, key: String) -> UIImage? {
        let cacheKey = key as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        guard let data = data(from: dataUrl),
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
