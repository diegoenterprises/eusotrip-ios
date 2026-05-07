//
//  EusoQR.swift
//  EusoTrip — Brand-tinted QR code primitive + role-aware payload builder.
//
//  One generator, every surface. Drop `EusoQRView(payload: …)` anywhere
//  and the QR renders with the EusoTrip blue→magenta gradient on a
//  white background. Founder mandate 2026-05-06 — every QR surface
//  needs to work, must be role-agnostic and role-aware. The payload
//  builder produces canonical Universal Links the iOS app already
//  routes via `eusotrip://` + `https://eusotrip.com/`, so the same
//  QR scans into either platform.
//
//  Why CoreImage instead of a third-party SDK:
//    • Zero dep weight, zero network round-trip
//    • `CIQRCodeGenerator` ships in iOS 7+
//    • Error-correction level H (30 % recoverable) tolerates the
//      brand-color tint + finder-pattern occlusion without breaking
//      camera scans (verified on physical scanner @ 18 in 2026-04-25)
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Renderer (CoreImage)

/// Pure-CoreImage QR renderer. Returns a square monochrome bitmap; the
/// SwiftUI wrapper composites the brand gradient on top via mask.
enum EusoQRGenerator {
    /// Generates a `UIImage` for `text`. Caches by (text, scale) so
    /// re-renders during scroll don't re-run the filter pipeline.
    static func image(for text: String, scale: CGFloat = 10) -> UIImage? {
        let key = NSString(string: "\(text)|\(scale)")
        if let hit = cache.object(forKey: key) { return hit }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"
        guard let ci = filter.outputImage else { return nil }
        let up = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(up, from: up.extent) else { return nil }
        let img = UIImage(cgImage: cg)
        cache.setObject(img, forKey: key)
        return img
    }

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 64
        return c
    }()
}

// MARK: - SwiftUI view

/// Brand-tinted QR. Renders the EusoTrip diagonal gradient where the
/// QR has "on" modules, white elsewhere. Same finder patterns + same
/// contrast a default black QR would have, just with the brand
/// applied via mask.
struct EusoQRView: View {
    let payload: String
    var size: CGFloat = 240
    var cornerRadius: CGFloat = 16

    var body: some View {
        ZStack {
            Color.white
            if let qr = EusoQRGenerator.image(for: payload) {
                LinearGradient.diagonal
                    .mask(
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
        )
        .accessibilityLabel("QR code")
        .accessibilityValue(payload)
    }
}

// MARK: - Role-aware payload builder

/// Canonical role enum used by the QR builder. Every callable surface
/// (load, agreement, settlement, BOL, invite, profile, run-ticket,
/// EusoTicket, escort) takes a `EusoRoleScope` so the receiving side
/// can decode the role context out of the URL without a second fetch.
enum EusoRoleScope: String, Hashable {
    case shipper
    case driver
    case carrier        // CATALYST
    case broker
    case dispatch
    case escort
    case terminal
    case factoring
    case compliance
    case safety
    case admin
    case any            // generic — receiving side resolves from auth context
}

/// All payload kinds the QR system supports today. Centralises the
/// URL grammar so the same constant is used by the producer (this
/// file) and the consumer (`ShipperWebToNativeMap`,
/// `DriverDeepLinkHandler`, server `auth.qr.*` procedures).
enum EusoQRKind {
    /// Pickup/delivery credential for a load id.
    /// `eusotrip://load/<id>?role=<scope>&context=<credential|view>`
    case loadCredential(loadId: String, mode: CredentialMode = .credential)
    /// View an agreement via Continuity / web.
    /// `https://eusotrip.com/agreements/<id>?role=<scope>`
    case agreement(id: String)
    /// View a settlement.
    /// `https://eusotrip.com/settlements/<id>?role=<scope>`
    case settlement(id: String)
    /// Run-ticket / haul receipt / BOL — receiving party scans on yard.
    /// `eusotrip://eusoticket/<kind>/<id>?role=<scope>`
    case eusoTicket(kind: TicketKind, id: String)
    /// Invite — referral / catalyst-onboard / driver-onboard.
    /// `https://eusotrip.com/invite/<code>?role=<scope>&kind=<inviteKind>`
    case invite(code: String, kind: InviteKind)
    /// Profile / business card — generic identity hand-off.
    /// `https://eusotrip.com/u/<userId>?role=<scope>`
    case profile(userId: String)
    /// Escort pairing — UWB hand-off bootstrap.
    /// `eusotrip://escort/pair/<sessionId>?role=<scope>`
    case escortPairing(sessionId: String)
    /// Free-form payload (any URL or string). Used by surfaces that
    /// already have a fully-formed URL (e.g. third-party Apple
    /// PassKit pkpass bundle URL).
    case raw(text: String)

    enum CredentialMode: String { case credential, view }
    enum TicketKind: String { case bol, runticket, haulreceipt, pod }
    enum InviteKind: String { case shipper, catalyst, driver, broker, escort, terminal, generic }

    /// Build the canonical URL string the QR encodes.
    func payload(role: EusoRoleScope) -> String {
        switch self {
        case let .loadCredential(loadId, mode):
            return "eusotrip://load/\(escape(loadId))?role=\(role.rawValue)&context=\(mode.rawValue)"
        case let .agreement(id):
            return "https://eusotrip.com/agreements/\(escape(id))?role=\(role.rawValue)"
        case let .settlement(id):
            return "https://eusotrip.com/settlements/\(escape(id))?role=\(role.rawValue)"
        case let .eusoTicket(kind, id):
            return "eusotrip://eusoticket/\(kind.rawValue)/\(escape(id))?role=\(role.rawValue)"
        case let .invite(code, kind):
            return "https://eusotrip.com/invite/\(escape(code))?role=\(role.rawValue)&kind=\(kind.rawValue)"
        case let .profile(userId):
            return "https://eusotrip.com/u/\(escape(userId))?role=\(role.rawValue)"
        case let .escortPairing(sessionId):
            return "eusotrip://escort/pair/\(escape(sessionId))?role=\(role.rawValue)"
        case let .raw(text):
            return text
        }
    }

    private func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }
}

/// Convenience initializer for the common case: callers pass the
/// `kind` + `role` and we wire the payload string for them. Equivalent
/// to `EusoQRView(payload: kind.payload(role: role))` but reads better
/// at the call site:
///
///     EusoQRView(kind: .loadCredential(loadId: load.id), role: .shipper)
///
extension EusoQRView {
    init(
        kind: EusoQRKind,
        role: EusoRoleScope,
        size: CGFloat = 240,
        cornerRadius: CGFloat = 16
    ) {
        self.payload = kind.payload(role: role)
        self.size = size
        self.cornerRadius = cornerRadius
    }
}

#Preview("EusoQR · load credential · shipper") {
    EusoQRView(
        kind: .loadCredential(loadId: "LD-260427-A38FB12C7E"),
        role: .shipper
    )
    .padding(20)
    .background(Color.black)
}

#Preview("EusoQR · invite · catalyst") {
    EusoQRView(
        kind: .invite(code: "EUSO-AB12CD", kind: .catalyst),
        role: .any,
        size: 220
    )
    .padding(20)
    .background(Color.black)
}
