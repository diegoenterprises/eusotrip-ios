//
//  239_ShipperApplePayWallet.swift
//  EusoTrip iOS — Shipper Apple Pay / PassKit / Wallet authoring
//                 (§35.3 Arc L)
//
//  REDESIGNED to the Design Authority level (founder mandate 722): the
//  Apple Pay / Wallet surface is now bespoke to the FOUNDER-APPROVED
//  EusoWallet design language (290_WalletHome / 291_EusoWalletDetail).
//  It shares the EusoWalletComponents primitives (WalletGlyph / WalletEyebrow
//  / WalletShimmer / eusoCard surfaces) so it speaks the same volumetric,
//  alive, trustworthy money-card voice as the rest of the wallet — not the
//  prior flat "AI-coded basic" list. Every section glyph is a drawn
//  `WalletGlyph` Path; ZERO SF Symbols on this surface.
//
//  SVG/design owns the LOOK · iOS owns the FUNCTION (bespoke-conformance
//  bridge): the visual layer was rebuilt to the wallet language while EVERY
//  data fetch, proc call, action, navigation, and @State is preserved 1:1:
//
//    • Data:   wallet.shipperPassesSnapshot (active + passes) +
//              wallet.listPaymentMethods (live Stripe Customer cards).
//    • Actions: tapAddToWallet → EusoWalletPassService.addPass (PassKit) ·
//               tapPassRow → same PassKit flow · tapPaymentMethod →
//               wallet.setDefaultPaymentMethod (Stripe default-card flip) ·
//               tapManageApplePay → nav-swap to 295 (the already-fixed
//               Manage-Apple-Pay routing, untouched).
//    • State:  inlineQrPayload / inlineShortCode / passBanner* /
//              activePass / passes / paymentMethods / snapshotPhase /
//              settingDefaultMethodId — all preserved.
//
//  Surface: per-load Wallet pickup-credential pass (hero) + the live
//  passes-in-Wallet list + Apple Pay methods (live Stripe cards), both on
//  the Eusorone Technologies merchant account. ZERO fabrication — real data
//  or an honest em-dash.
//
//  iOS framework binding (unchanged):
//    PassKit (PKPass / PKPassLibrary / PKAddPassesViewController) +
//    Apple Pay (PKPaymentRequest / PKPaymentAuthorizationViewController).
//    Each .pkpass is signed against the Eusorone PassKit certificate and
//    carries: serialNumber = LD-id, primaryFields = lane, secondaryFields =
//    ETA, auxiliaryFields = carrier + escrow, barcodes[0].message =
//    "eusotrip://load/LD-..." for gate-scanner verification.
//
//  Both #Preview blocks (Dark + Light) ship per §11.4 doctrine.
//

import SwiftUI

// MARK: - Screen

struct ShipperApplePayWallet: View {
    @Environment(\.palette) var palette
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Inline QR payload, set when `EusoWalletPassService` falls back
    /// to the no-pkpass branch. The hero pickup card swaps from the
    /// canonical credential deeplink to a live `EusoQRView` whenever this
    /// is non-nil.
    @State var inlineQrPayload: String? = nil
    /// 5-digit fallback code shown next to the QR for the "type-it"
    /// path when the gate scanner can't read the QR (camera issue,
    /// glare, rooted device with no camera permission).
    @State var inlineShortCode: String? = nil
    /// The GATE CODE for the active pickup credential — the 5-digit
    /// `shortCode` the server PassKit signer mints (and stamps onto the
    /// .pkpass) via `eusoWallet.createPickupCredential`. Surfaced as a
    /// prominent field on the hero card so the shipper can read it (or
    /// dictate it to the gate) without first triggering Add-to-Wallet.
    /// Honest em-dash until the credential mints; never fabricated.
    @State var gateCode: String? = nil
    /// True while the gate code is being minted for the active pass, so
    /// the hero field shows a bounded loading dash rather than a blank.
    @State private var gateCodeLoading: Bool = false
    /// Inline banner — shown after every Add-to-Wallet attempt so the
    /// user always knows the result. Auto-clears after 4 s.
    @State var passBannerText: String? = nil
    @State var passBannerKind: WalletBannerKind = .info

    enum WalletBannerKind { case success, info, error }

    // ── Live wallet state — fetched from the server at .task ──────
    // Backed by wallet.shipperPassesSnapshot (active + 3 passes) and
    // wallet.listPaymentMethods (Stripe Customer cards). The hardcoded
    // demo arrays that used to live here are gone — every row on this
    // screen now reflects the signed-in shipper's actual loads + cards.

    @State private var activePass: ActiveWalletPass? = nil
    @State private var passes: [WalletPass] = []
    @State private var paymentMethods: [PaymentMethod] = []
    @State private var snapshotPhase: SnapshotPhase = .loading
    @State private var settingDefaultMethodId: String? = nil

    enum SnapshotPhase: Equatable {
        case loading
        case loaded
        case empty       // no live loads on file
        case error(String)
    }

    private var isDark: Bool { palette.bgPage == Theme.dark.bgPage }

    /// Numeric DB load id of the active pass — the stable key the list
    /// rows match against to highlight the active credential. (The
    /// string `id` carries a "pass_" prefix that never matched a list
    /// row's reference, so the active-row highlight relied on this.)
    private var activePassLoadId: Int? {
        activePass.flatMap { Int($0.apiLoadId) }
    }

    /// Eyebrow counter — recomputes from live state instead of a
    /// hardcoded "3 PASSES · 1 ACTIVE" string. When there are no
    /// passes the screen still reads "0 PASSES · 0 ACTIVE" instead
    /// of lying about installed Wallet bundles.
    private var counterEyebrow: String {
        let activeCount = activePass != nil ? 1 : 0
        return "\(passes.count) PASSES · \(activeCount) ACTIVE"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                header

                // ── Active pass hero ───────────────────────────────────
                // Renders the bespoke gradient pickup-credential money-card
                // with the live QR + Add-to-Wallet CTA when the shipper has
                // a live load. Honest empty/loading/error states otherwise —
                // never a fake hardcoded pass.
                if let pass = activePass {
                    heroPassCard(for: pass)
                } else if snapshotPhase == .empty {
                    emptyHeroCard
                } else if snapshotPhase == .loading {
                    loadingHeroCard
                } else if case .error(let msg) = snapshotPhase {
                    errorHeroCard(message: msg)
                }

                // ── Pass list ──────────────────────────────────────────
                if !passes.isEmpty {
                    passesCard
                }

                // ── Apple Pay methods ──────────────────────────────────
                paymentMethodsSection

                // ── Manage Apple Pay (the already-fixed 295 routing) ───
                manageSection

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .overlay(alignment: .top) { passBannerOverlay }
        .animation(.easeInOut(duration: 0.2), value: passBannerText)
        .task { await loadAll() }
        .eusoRefreshable { await loadAll() }
    }

    // MARK: — Header (290 wallet-home recipe: eyebrow + heavy title +
    //          drawn iridescent wallet mark)

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                WalletEyebrow(glyph: .wallet, text: "SHIPPER · APPLE PAY WALLET")
                Text("Wallet")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(counterEyebrow)
                    .font(.system(size: 10, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .accessibilityLabel("\(passes.count) Apple Wallet passes. \(activePass != nil ? "One is the active pickup credential." : "None currently active.")")
            }
            Spacer(minLength: 0)
            // Iridescent brand mark — drawn wallet glyph (no SF Symbol).
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 38, height: 38)
                WalletGlyph(kind: .wallet, size: 18, tint: AnyShapeStyle(Color.white), lineWidth: 1.6)
            }
            .shadow(color: Brand.magenta.opacity(isDark ? 0.45 : 0.22), radius: 10, x: 0, y: 4)
        }
    }

    // MARK: — Empty / loading / error hero states (bespoke, drawn glyphs)

    private var loadingHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            WalletEyebrow(glyph: .wallet, text: "ACTIVE PASS")
            WalletShimmer(height: 18, radius: 6).frame(width: 140)
            WalletShimmer(height: 40, radius: 12)
            WalletShimmer(height: 12, radius: 5).frame(width: 180)
            HStack(spacing: 12) {
                WalletShimmer(height: 36, radius: Radius.md).frame(width: 36)
                WalletShimmer(height: 12, radius: 5)
                WalletShimmer(height: 22, radius: 11).frame(width: 120)
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    private var emptyHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    WalletGlyph(kind: .wallet, size: 20, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.6)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No active pickup credential")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("Nothing in-transit yet")
                        .font(EType.micro).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            Text("Post a load and accept a carrier's bid. We'll mint a signed .pkpass for your gate scanner the moment the load goes in-transit.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "204"])
            } label: {
                HStack(spacing: 8) {
                    WalletGlyph(kind: .spark, size: 14, tint: AnyShapeStyle(Color.white), lineWidth: 1.7)
                    Text("Post a load").font(EType.bodyStrong).foregroundStyle(.white)
                }
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background(LinearGradient.diagonal)
                .overlay(alignment: .top) {
                    Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .clipShape(Capsule())
                .shadow(color: Brand.blue.opacity(isDark ? 0.3 : 0.14), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }

    private func errorHeroCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Brand.danger.opacity(0.12))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Brand.danger.opacity(0.40), lineWidth: 1)
                    WalletGlyph(kind: .pulse, size: 18, tint: AnyShapeStyle(Brand.danger), lineWidth: 1.6)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Couldn't load wallet").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(message).font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button { Task { await loadAll() } } label: {
                Text("Retry")
                    .font(.system(size: 12, weight: .heavy))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }

    // MARK: — Apple Pay methods section

    @ViewBuilder
    private var paymentMethodsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                WalletEyebrow(glyph: .bank, text: "APPLE PAY")
                Spacer(minLength: 0)
                Text("\(paymentMethods.count) METHOD\(paymentMethods.count == 1 ? "" : "S")")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            if paymentMethods.isEmpty {
                emptyPaymentMethodsCard
            } else {
                VStack(spacing: 8) {
                    ForEach(paymentMethods) { method in
                        PaymentCardRow(
                            method: method,
                            isSettingDefault: settingDefaultMethodId == method.id,
                            onRowTap: { tapPaymentMethod(method) }
                        )
                    }
                }
            }
        }
    }

    private var emptyPaymentMethodsCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.blue.opacity(0.12), Brand.magenta.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                WalletGlyph(kind: .bank, size: 18, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.6)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("No payment methods on file")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("Add a card via Apple Pay or Plaid to fund escrow + accept settlements.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }

    // MARK: — Data loading (UNCHANGED — same two procs, same mapping)

    @MainActor
    private func loadAll() async {
        snapshotPhase = .loading
        do {
            async let snapshotTask: WalletAPI.ShipperPassesSnapshot = EusoTripAPI.shared.wallet.shipperPassesSnapshot()
            async let methodsTask: [WalletAPI.PaymentMethodRow] = EusoTripAPI.shared.wallet.listPaymentMethods()
            let snap = try await snapshotTask
            let mts = try await methodsTask

            passes = snap.passes.map { row in
                WalletPass(
                    // Sanitized human reference for the row's mono id line —
                    // never the raw "MATRIX-50 ROW 1" seed cohort tag.
                    id: Self.passReference(row),
                    loadId: row.loadId,
                    tilePrefix: Self.cleanWalletLabel(row.tilePrefix),
                    lane: row.lane,
                    spec: Self.cleanWalletLabel(row.spec),
                    installedNote: row.installedNote,
                    status: WalletPassStatus.fromServer(row.status)
                )
            }
            activePass = snap.active.map(Self.heroFromRow)
            paymentMethods = mts.map(Self.methodFromRow)
            snapshotPhase = (snap.active == nil && snap.passes.isEmpty) ? .empty : .loaded
        } catch {
            passes = []
            activePass = nil
            paymentMethods = []
            snapshotPhase = .error((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }

        // Mint / fetch the GATE CODE for the active pickup credential so the
        // hero card can surface it as a prominent field. Best-effort: a nil
        // result leaves an honest em-dash — never a fabricated PIN. Safe on
        // the error path too: with no `activePass` it just clears the code.
        await loadGateCode()
    }

    /// Fetch the active pass's gate code — the `shortCode` the server
    /// PassKit signer mints via `eusoWallet.createPickupCredential` (RBAC:
    /// the shipper is a party on the load). `createPickupCredential` is
    /// idempotent enough for this read-through: it returns a usable code
    /// even when .pkpass signing/storage is unconfigured. Bounded; honest
    /// em-dash on any failure or when there's no active pass.
    @MainActor
    private func loadGateCode() async {
        guard let pass = activePass else { gateCode = nil; return }
        gateCodeLoading = true
        defer { gateCodeLoading = false }
        do {
            // MUST be the numeric apiLoadId — the server parseInt()s it.
            let cred = try await EusoTripAPI.shared.createPickupCredential(loadId: pass.apiLoadId)
            gateCode = cred.shortCode.isEmpty ? nil : cred.shortCode
        } catch {
            // Honest em-dash; the field renders "—" rather than a fake code.
            gateCode = nil
        }
    }

    /// Strip dev/seed batch tags + bracket/key=value tokens out of any
    /// server-supplied display string before it reaches the UI. Mirrors
    /// 205_ShipperLoadDetail.cleanLabel(_:) — copied here (file-scoped)
    /// so the wallet eyebrow + LOAD ID never surface a seed cohort tag
    /// like "MATRIX-50 ROW 1" as if it were a real pass reference.
    /// Display-layer only; never feed the result back to the server.
    private static func cleanWalletLabel(_ s: String) -> String {
        var out = s
        // Drop "[enum_key]" bracket tokens (with any leading whitespace).
        out = out.replacingOccurrences(
            of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
        // Drop "key=value" tokens (vertical=truck, …) + a leading bullet.
        out = out.replacingOccurrences(
            of: #"\s*[·•]?\s*[A-Za-z_-]+=\S+"#, with: "", options: .regularExpression)
        // Drop demo batch-cohort tags ("MATRIX-50 ROW 1", "MATRIX-50-2026-…")
        // — these are seed identifiers, never real pass references.
        out = out.replacingOccurrences(
            of: #"(?i)\bMATRIX-?\d*(\s+ROW\s+\d+|[\w-]*)"#, with: "", options: .regularExpression)
        // Collapse any doubled separators the removals left behind.
        out = out.replacingOccurrences(
            of: #"\s*·\s*·\s*"#, with: " · ", options: .regularExpression)
        return out.trimmingCharacters(in: CharacterSet(charactersIn: " ·•\u{2014}-"))
    }

    /// The human load reference shown on the pass (eyebrow + LOAD ID
    /// field). Prefers the server `loadNumber` ("LD-…"); falls back to a
    /// sanitized `id` ONLY when it reads like a real load token; finally
    /// derives "LD-<numericId>" so the card never shows a seed cohort tag
    /// nor an empty placeholder.
    private static func passReference(_ row: WalletAPI.ShipperPassRow) -> String {
        if let ln = row.loadNumber {
            let cleaned = cleanWalletLabel(ln)
            if !cleaned.isEmpty { return cleaned }
        }
        let cleanedId = cleanWalletLabel(row.id)
        // Accept the id only if it survived sanitizing as a real load
        // reference (contains a digit and isn't a leftover cohort word).
        if !cleanedId.isEmpty,
           cleanedId.rangeOfCharacter(from: .decimalDigits) != nil,
           cleanedId.range(of: #"(?i)^(MATRIX|ROW|DEMO|SEED|TEST)\b"#, options: .regularExpression) == nil {
            return cleanedId
        }
        return "LD-\(row.loadId)"
    }

    /// Translate a server `ShipperPassRow` into the hero card's
    /// ActiveWalletPass shape. Adds the human-formatted ETA + the
    /// "ACTIVE PASS" eyebrow (with the load reference when present).
    private static func heroFromRow(_ row: WalletAPI.ShipperPassRow) -> ActiveWalletPass {
        let etaText: String = {
            guard let iso = row.deliveryDate ?? row.pickupDate else { return "TBD" }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let d = f.date(from: iso) ?? {
                f.formatOptions = [.withInternetDateTime]
                return f.date(from: iso)
            }() ?? Date()
            let date = DateFormatter()
            date.dateFormat = "MMM d"
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .short
            return "\(date.string(from: d)) · \(rel.localizedString(for: d, relativeTo: Date()))"
        }()

        let equipmentLine: String = {
            let parts: [String?] = [
                row.equipmentType?.replacingOccurrences(of: "_", with: " "),
                row.unNumber.map { "UN\($0)" },
                row.cargoType,
            ]
            return parts.compactMap { $0 }.joined(separator: " · ")
        }()

        let carrierLine: String = {
            switch (row.carrierName, row.carrierMc) {
            case let (n?, mc?): return "\(n) · MC-\(mc)"
            case let (n?, nil): return n
            case (nil, let mc?): return "MC-\(mc)"
            default: return "Carrier pending"
            }
        }()

        let escrowLine: String = row.rate.map { "Escrow funded · $\($0)" } ?? "Escrow pending"

        // Single sanitized human reference — drives both the LOAD ID
        // field on the card and the section eyebrow, so a seed cohort
        // tag ("MATRIX-50 ROW 1") can never appear in either place.
        let reference = passReference(row)

        return ActiveWalletPass(
            id: "pass_\(row.loadId)",
            issuerLine: "EUSORONE TECHNOLOGIES",
            title: "Pickup Credential",
            loadId: reference,
            apiLoadId: String(row.loadId),
            lane: row.lane,
            eta: etaText,
            equipment: equipmentLine.isEmpty ? "Equipment pending" : equipmentLine,
            carrierLine: carrierLine,
            escrowLine: escrowLine,
            carrierTier: reference.last.map(String.init) ?? "A",
            ctaLabel: "Add to Wallet",
            // Section eyebrow for the active pass — always the clean
            // load reference ("ACTIVE PASS · LD-…"), never the raw
            // server seed id.
            matrixRowLabel: "ACTIVE PASS · \(reference)"
        )
    }

    private static func methodFromRow(_ row: WalletAPI.PaymentMethodRow) -> PaymentMethod {
        let brand = PaymentBrand.from(row.brand)
        let mm = String(format: "%02d", row.expMonth)
        let yy = String(format: "%02d", row.expYear % 100)
        let nameLine = row.billingName ?? "EusoTrip Member"
        let tag: PaymentTag = row.isDefault ? .defaultMethod : .backup
        return PaymentMethod(
            id: row.id,
            brand: brand,
            maskedPAN: "\(brand.displayName) \u{2022}\u{2022}\u{2022}\u{2022} \(row.last4)",
            spec: "\(nameLine) · \(row.isDefault ? "default" : "backup") · expires \(mm)/\(yy)",
            tag: tag
        )
    }

    // MARK: - HERO PASS CARD (active Wallet pass — bespoke money-card)
    //
    // The pickup credential rendered in the wallet money-card idiom: a
    // layered volumetric gradient card (aurora bloom + sheen sweep +
    // top-rim catch-light + dual iridescent glow) carrying the LOAD ID
    // numeral, the lane, the live ETA + equipment, the carrier band, the
    // genuine gate QR, and the Add-to-Wallet CTA. Same data + same action
    // (tapAddToWallet → PassKit) as before; only the surface is elevated.

    private func heroPassCard(for pass: ActiveWalletPass) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            // ── issuer header strip + Apple Pay chip ──
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        WalletGlyph(kind: .wallet, size: 12, tint: AnyShapeStyle(Color.white.opacity(0.9)), lineWidth: 1.4)
                        Text(pass.issuerLine)
                            .font(.system(size: 8, weight: .heavy)).tracking(1.2)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Text(pass.title)
                        .font(.system(size: 13, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                ZStack {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.75)
                    Text("Pay")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 20)
            }

            // ── LOAD ID / LANE + the genuine gate QR ──
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("LOAD ID")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.top, 16)
                    Text(pass.loadId)
                        .font(.system(size: 18, weight: .heavy, design: .monospaced)).tracking(0.4)
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.top, 3)

                    Text("LANE")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.top, 14)
                    Text(pass.lane)
                        .font(.system(size: 21, weight: .heavy)).tracking(-0.3)
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.top, 2)

                    HStack(alignment: .top, spacing: 18) {
                        heroField("ETA", pass.eta, mono: true)
                        heroField("EQUIPMENT", pass.equipment, mono: false)
                    }
                    .padding(.top, 14)

                    // GATE CODE — the prominent credential the gate scanner /
                    // yard worker verifies. The server PassKit signer mints
                    // this 5-digit shortCode and stamps it on the .pkpass;
                    // we surface it here so the shipper can read or dictate it
                    // without first installing the pass. Honest em-dash until
                    // the credential mints — never a fabricated PIN.
                    gateCodeField
                        .padding(.top, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Real QR via the shared EusoQR primitive on a white chip.
                // When Wallet signing is offline the service hands back the
                // server-signed credential token; we render THAT (the exact
                // payload the gate scanner verifies). Before any mint we fall
                // back to the deterministic load-credential deeplink, which
                // also scans cleanly. Founder mandate — every QR must work.
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white)
                            .frame(width: 96, height: 96)
                        EusoQRView(
                            kind: inlineQrPayload.map { .raw(text: $0) }
                                ?? .loadCredential(
                                    loadId: pass.apiLoadId,
                                    mode: .credential
                                ),
                            role: .shipper,
                            size: 84,
                            cornerRadius: 6
                        )
                    }
                    if let code = inlineShortCode {
                        Text(code)
                            .font(EType.mono(.micro)).tracking(2.0)
                            .foregroundStyle(.white)
                            .accessibilityLabel("Gate fallback code \(code.map(String.init).joined(separator: " "))")
                    }
                }
                .padding(.top, 14)
            }

            // ── carrier band + Add-to-Wallet CTA ──
            Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
                .padding(.top, 14)

            HStack(alignment: .center, spacing: 12) {
                // tier badge — drawn, gradient-inverse on the gradient card
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(0.22))
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(0.30), lineWidth: 1)
                    Text(pass.carrierTier)
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pass.carrierLine)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.78)
                    Text(pass.escrowLine)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1).minimumScaleFactor(0.78)
                }
                Spacer(minLength: 0)

                Button(action: tapAddToWallet) {
                    HStack(spacing: 6) {
                        WalletGlyph(kind: .wallet, size: 13, tint: AnyShapeStyle(Brand.blue), lineWidth: 1.6)
                        Text(pass.ctaLabel)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.blue)
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add the active pickup credential to Apple Wallet. Installs a .pkpass bundle bound to \(pass.loadId).")
            }
            .padding(.top, 14)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient.diagonal
                RadialGradient(colors: [.white.opacity(0.30), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 340)
                LinearGradient(colors: [.clear, .white.opacity(0.10), .clear],
                               startPoint: .top, endPoint: .bottomTrailing)
            }
        }
        .overlay(alignment: .top) {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        }
        .clipShape(shape)
        .shadow(color: Brand.blue.opacity(isDark ? 0.42 : 0.18), radius: 20, x: 0, y: 10)
        .shadow(color: Brand.magenta.opacity(isDark ? 0.30 : 0.12), radius: 24, x: 0, y: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(pass.matrixRowLabel ?? "Active pass")
    }

    private func heroField(_ label: String, _ value: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.78)
                .modifier(MonoDigit(on: mono))
        }
    }

    /// The prominent GATE CODE field on the hero card — a glassy chip
    /// carrying the large, spaced, monospaced PIN the gate verifies. Reads
    /// the live `gateCode` (server `shortCode`); shows a bounded loading dash
    /// while minting and an honest "— · ISSUED AT THE GATE" when none yet.
    private var gateCodeField: some View {
        let display: String = gateCode ?? (gateCodeLoading ? "·····" : "—")
        let spaced = gateCode.map { $0.map(String.init).joined(separator: "  ") } ?? display
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GATE CODE")
                    .font(.system(size: 8, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.78))
                Text(spaced)
                    .font(.system(size: 22, weight: .heavy, design: .monospaced)).tracking(2.0)
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityLabel(gateCode.map { "Gate code \($0.map(String.init).joined(separator: " "))" }
                                        ?? "Gate code issued at the gate")
                if gateCode == nil && !gateCodeLoading {
                    Text("Issued when the credential mints")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(.white.opacity(0.16))
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(.white.opacity(0.28), lineWidth: 1)
            }
        )
    }

    // MARK: — Passes list (bespoke rows in a carded ledger)

    private var passesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                WalletEyebrow(glyph: .pulse, text: "PASSES")
                Spacer(minLength: 0)
                Text("\(passes.count) IN WALLET")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(passes.enumerated()), id: \.element.id) { idx, pass in
                    PassRow(
                        pass: pass,
                        isActive: pass.loadId == activePassLoadId,
                        showDivider: idx < passes.count - 1,
                        onRowTap: { tapPassRow(pass) }
                    )
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    // MARK: — Manage section (the already-fixed 295 routing — UNCHANGED)

    private var manageSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            WalletEyebrow(glyph: .pie, text: "MANAGE").padding(.leading, 2)
            Button(action: tapManageApplePay) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                        WalletGlyph(kind: .bank, size: 16, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
                    }
                    .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Manage Apple Pay integration")
                            .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Text("Per-card · per-pass settings · Payment Methods")
                            .font(EType.micro).foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 0)
                    WalletGlyph(kind: .chevron, size: 13, tint: AnyShapeStyle(palette.textTertiary), lineWidth: 1.5)
                }
                .padding(.horizontal, Space.s3).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.md, intensity: .whisper)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Manage Apple Pay integration. Per-card and per-pass settings live in Payment Methods.")

            footer
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Powered by Apple Pay · PassKit · Wallet")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
            Text("Eusorone Technologies, Inc")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, Space.s2)
    }

    // MARK: - Banner overlay (drawn glyphs — no SF Symbols)

    @ViewBuilder
    private var passBannerOverlay: some View {
        if let text = passBannerText {
            walletBanner(text, kind: passBannerKind)
                .padding(.top, Space.s3)
                .padding(.horizontal, Space.s4)
        }
    }

    @ViewBuilder
    private func walletBanner(_ text: String, kind: WalletBannerKind) -> some View {
        let tint: Color = kind == .success ? Brand.success : kind == .error ? Brand.danger : Brand.blue
        let glyph: WalletGlyph.Kind = kind == .success ? .spark : kind == .error ? .pulse : .bolt
        return HStack(alignment: .top, spacing: Space.s2) {
            ZStack {
                Circle().fill(tint.opacity(0.14)).frame(width: 26, height: 26)
                WalletGlyph(kind: glyph, size: 14, tint: AnyShapeStyle(tint), lineWidth: 1.6)
            }
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md, intensity: .standard)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Tap handlers (§20.4 no dead buttons — UNCHANGED behavior)

    private func tapAddToWallet() {
        // Guard against the empty / loading hero state — the button
        // shouldn't be reachable there but defensive nil-check keeps
        // the no-active-pass path from crashing if the binding leaks.
        guard let pass = activePass else { return }

        NotificationCenter.default.post(
            name: .eusoShipperWalletAddPass,
            object: nil,
            userInfo: [
                "source": "239_ShipperApplePayWallet",
                "passId": pass.id,
                "loadId": pass.apiLoadId,
                "carrierLine": pass.carrierLine,
            ]
        )
        // Hand off to PassKit. The service handles the
        //   server credential mint → .pkpass fetch → PKPass parse →
        //   PKAddPassesViewController present
        // chain, plus a graceful fallback to the inline QR + 5-digit
        // shortCode card when the .pkpass signing pipeline is offline.
        // MUST be the numeric apiLoadId — the server parseInt()s it.
        let loadId = pass.apiLoadId
        Task {
            let result = await EusoWalletPassService.shared.addPass(forLoadId: loadId)
            await MainActor.run { applyPassResult(result) }
        }
    }

    private func tapPassRow(_ pass: WalletPass) {
        NotificationCenter.default.post(
            name: .eusoShipperWalletPassRow,
            object: nil,
            userInfo: [
                "source": "239_ShipperApplePayWallet",
                "passId": pass.id,
                "loadId": String(pass.loadId),
                "isActivePass": pass.loadId == activePassLoadId,
                "shipperCompanyId": 1
            ]
        )
        // Tapping any pass row in the list also routes to the same
        // PassKit flow — every pass should add to Apple Wallet, not
        // open Safari. Numeric loadId — server parseInt()s it.
        let loadId = String(pass.loadId)
        Task {
            let result = await EusoWalletPassService.shared.addPass(forLoadId: loadId)
            await MainActor.run { applyPassResult(result) }
        }
    }

    /// Apply the result of `EusoWalletPassService.addPass` to local
    /// state. `presented` needs no UI work — the system Apple Wallet
    /// sheet is already up. The other two cases drive an inline
    /// banner so the user always knows what happened (no silent
    /// failures, per the no-dead-buttons doctrine).
    @MainActor
    private func applyPassResult(_ result: EusoWalletPassResult) {
        // How long the banner lingers. The signing-offline instruction
        // ("present the QR or code … at the gate") needs to be readable,
        // so it stays up longer; success/error auto-clear faster. In the
        // offline case the QR + short code also remain on the hero card
        // permanently, so the credential stays usable after the banner.
        var dwell: UInt64 = 4_000_000_000
        switch result {
        case .presented:
            passBannerKind = .success
            passBannerText = "Apple Wallet is open with the signed pass"
        case .updated:
            passBannerKind = .success
            passBannerText = "The installed Apple Wallet pass now uses your selected design"
        case .signingUnavailable(let qrPayload, let shortCode):
            passBannerKind = .info
            passBannerText = "Apple Wallet signing is offline — present this in-app pass: scan the QR or enter code \(shortCode) at the gate."
            inlineQrPayload = qrPayload
            inlineShortCode = shortCode
            // Keep the hero's GATE CODE field in sync with the freshly-minted
            // credential's shortCode (same value the .pkpass is stamped with).
            gateCode = shortCode
            dwell = 8_000_000_000
        case .failure(let message):
            passBannerKind = .error
            passBannerText = message
        }
        // Auto-clear so the banner doesn't linger indefinitely.
        Task {
            try? await Task.sleep(nanoseconds: dwell)
            await MainActor.run { passBannerText = nil }
        }
    }

    /// Tapping a card row sets it as the Stripe Customer's default
    /// payment method. The web redirect was removed — real platform
    /// state lives in Stripe, and the iOS row should be the editor.
    private func tapPaymentMethod(_ method: PaymentMethod) {
        // No-op if already default — the row tap shouldn't waste a
        // round-trip on a write that does nothing.
        guard method.tag != .defaultMethod else { return }
        // Disable concurrent taps while a default-flip is in flight.
        guard settingDefaultMethodId == nil else { return }

        NotificationCenter.default.post(
            name: .eusoShipperWalletPaymentMethod,
            object: nil,
            userInfo: [
                "source": "239_ShipperApplePayWallet",
                "paymentMethodId": method.id,
                "brand": method.brand.rawValue,
                "isDefault": false,
            ]
        )

        settingDefaultMethodId = method.id
        Task {
            do {
                _ = try await EusoTripAPI.shared.wallet.setDefaultPaymentMethod(method.id)
                // Optimistic re-render — flip the tag locally then
                // re-fetch so the rest of the wallet (default-method-
                // dependent settlements) stays in sync.
                await MainActor.run {
                    paymentMethods = paymentMethods.map {
                        let isDefault = $0.id == method.id
                        // Rebuild the spec deterministically from its own
                        // fields rather than string-replacing the word.
                        // Format (see methodFromRow): "name · default|backup
                        // · expires mm/yy" — the three components are joined
                        // by " · ", so we swap only the middle token by index
                        // and leave the name + expiry exactly as they were.
                        // String-replacing collided when "default"/"backup"
                        // appeared in the billing name and double-flipped.
                        var parts = $0.spec.components(separatedBy: " · ")
                        if parts.count >= 2 {
                            parts[1] = isDefault ? "default" : "backup"
                        }
                        return PaymentMethod(
                            id: $0.id,
                            brand: $0.brand,
                            maskedPAN: $0.maskedPAN,
                            spec: parts.joined(separator: " · "),
                            tag: isDefault ? .defaultMethod : .backup
                        )
                    }
                    passBannerKind = .success
                    passBannerText = "Default card → \(method.maskedPAN)"
                }
                await loadAll()
            } catch {
                await MainActor.run {
                    passBannerKind = .error
                    passBannerText = "Couldn't change default card."
                }
            }
            await MainActor.run { settingDefaultMethodId = nil }
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run { passBannerText = nil }
            }
        }
    }

    /// Tapping the Manage pointer routes to the in-app Payment Methods
    /// screen (295) where Apple Pay cards/passes are actually managed — NOT
    /// the generic Settings screen (211), which dropped the user into an
    /// "abyss" with no focused Apple Pay surface (founder report). 295 is
    /// the real destination for per-card / per-pass management.
    /// (The already-fixed Manage-Apple-Pay routing — preserved verbatim.)
    private func tapManageApplePay() {
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap,
            object: nil,
            userInfo: [
                "screenId": "295",
                "source": "239_ShipperApplePayWallet",
                "deeplinkSection": "wallet",
            ]
        )
    }
}

// MARK: - MonoDigit helper (conditional monospacedDigit on the hero field)

private struct MonoDigit: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.monospacedDigit() } else { content }
    }
}

// MARK: - Domain models (file-scoped — wired by LiveDataStore from
//          ShipperWalletAPI.currentPasses() + wallet.listPaymentMethods)

private struct ActiveWalletPass {
    let id:          String
    let issuerLine:  String
    let title:       String
    /// Display load id — the "LD-1039" string shown in the card's
    /// LOAD ID field. Human-facing only.
    let loadId:      String
    /// Numeric DB load id (as a String) — what the server actually
    /// keys on. `createPickupCredential` does `parseInt(loadId)`, so
    /// sending the display "LD-1039" yields NaN → "Invalid loadId".
    /// Every API + QR call must use THIS, never `loadId`.
    let apiLoadId:   String
    let lane:        String
    let eta:         String
    let equipment:   String
    let carrierLine: String
    let escrowLine:  String
    let carrierTier: String
    let ctaLabel:    String
    /// Section eyebrow ("ACTIVE PASS · LD-…"). `heroFromRow` always
    /// populates a sanitized reference (never a raw seed cohort tag);
    /// the optional type just lets the call site fall back to the plain
    /// "ACTIVE PASS" label defensively.
    let matrixRowLabel: String?
}

private enum WalletPassStatus {
    case active
    case inTransit
    case escort
    case pending

    var label: String {
        switch self {
        case .active:    return "ACTIVE"
        case .inTransit: return "IN TRANSIT"
        case .escort:    return "ESCORT"
        case .pending:   return "PENDING"
        }
    }

    /// Status tint in the bespoke wallet palette — active reads gradient,
    /// the rest map to the brand semantic inks.
    var tint: Color {
        switch self {
        case .active:    return Brand.success
        case .inTransit: return Brand.blue
        case .escort:    return Brand.warning
        case .pending:   return Brand.info
        }
    }

    static func fromServer(_ raw: String) -> WalletPassStatus {
        switch raw.uppercased() {
        case "ACTIVE":       return .active
        case "IN_TRANSIT":   return .inTransit
        case "ESCORT":       return .escort
        default:             return .pending
        }
    }
}

private struct WalletPass: Identifiable {
    let id:            String       // "LD-1039" display id
    let loadId:        Int          // numeric DB id for API calls
    let tilePrefix:    String
    let lane:          String
    let spec:          String
    let installedNote: String
    let status:        WalletPassStatus
}

private enum PaymentBrand: String {
    case visa = "VISA"
    case mastercard = "MC"
    case amex = "AMEX"
    case discover = "DISC"
    case jcb = "JCB"
    case dinersclub = "DC"
    case unionpay = "UPI"
    case unknown = "CARD"

    var displayName: String {
        switch self {
        case .visa:        return "Visa"
        case .mastercard:  return "Mastercard"
        case .amex:        return "Amex"
        case .discover:    return "Discover"
        case .jcb:         return "JCB"
        case .dinersclub:  return "Diners"
        case .unionpay:    return "UnionPay"
        case .unknown:     return "Card"
        }
    }

    /// Map Stripe's lowercased brand string into the iOS enum.
    /// Stripe emits: visa, mastercard, amex, discover, jcb,
    /// diners, unionpay, unknown.
    static func from(_ raw: String) -> PaymentBrand {
        switch raw.lowercased() {
        case "visa":        return .visa
        case "mastercard":  return .mastercard
        case "amex", "american express", "american_express":
            return .amex
        case "discover":    return .discover
        case "jcb":         return .jcb
        case "diners", "dinersclub", "diners_club":
            return .dinersclub
        case "unionpay":    return .unionpay
        default:            return .unknown
        }
    }
}

private enum PaymentTag: Equatable {
    case defaultMethod
    case backup

    var label: String {
        switch self {
        case .defaultMethod: return "DEFAULT"
        case .backup:        return "BACKUP"
        }
    }
}

private struct PaymentMethod: Identifiable {
    let id:        String
    let brand:     PaymentBrand
    let maskedPAN: String
    let spec:      String
    let tag:       PaymentTag
}

// MARK: - PassRow (bespoke per-pass row — drawn LD-tile + lane + spec +
//          mono LD-id + drawn status dot; active variant gets the
//          iridescent gradient wash + a live pulse dot)

private struct PassRow: View {
    @Environment(\.palette) var palette
    let pass:        WalletPass
    let isActive:    Bool
    let showDivider: Bool
    let onRowTap:    () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onRowTap) {
                HStack(alignment: .center, spacing: 12) {
                    // drawn LD tile — gradient fill when active, soft otherwise
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isActive
                                  ? AnyShapeStyle(LinearGradient.diagonal)
                                  : AnyShapeStyle(palette.textPrimary.opacity(0.06)))
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(isActive
                                          ? AnyShapeStyle(Color.clear)
                                          : AnyShapeStyle(palette.iridescentHairline), lineWidth: 1)
                        Text(pass.tilePrefix)
                            .font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(0.4)
                            .foregroundStyle(isActive
                                             ? AnyShapeStyle(Color.white)
                                             : AnyShapeStyle(palette.textTertiary))
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pass.lane)
                            .font(EType.bodyStrong)
                            .foregroundStyle(isActive
                                             ? AnyShapeStyle(LinearGradient.diagonal)
                                             : AnyShapeStyle(palette.textPrimary))
                            .lineLimit(1).minimumScaleFactor(0.78)
                        Text(pass.spec)
                            .font(EType.micro)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.78)
                        Text("\(pass.id) · \(pass.installedNote)")
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(isActive
                                             ? AnyShapeStyle(LinearGradient.diagonal)
                                             : AnyShapeStyle(palette.textSecondary))
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // status — drawn dot + small-caps label, color-keyed
                    HStack(spacing: 5) {
                        Circle().fill(pass.status.tint).frame(width: 6, height: 6)
                        Text(pass.status.label)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(pass.status.tint)
                    }
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(pass.lane). \(pass.spec). \(pass.id), \(pass.installedNote). Status \(pass.status.label).\(isActive ? " Active pickup credential." : "")")

            if showDivider {
                Rectangle()
                    .fill(palette.iridescentHairline)
                    .frame(height: 1)
                    .opacity(0.4)
            }
        }
    }
}

// MARK: - PaymentCardRow (bespoke per-payment-method tile — drawn card
//          glyph in a brand-tinted vault + masked PAN + spec + DEFAULT/
//          BACKUP tag; carries an inline spinner while the default flip
//          is in flight)

private struct PaymentCardRow: View {
    @Environment(\.palette) var palette
    let method:           PaymentMethod
    let isSettingDefault: Bool
    let onRowTap:         () -> Void

    var body: some View {
        Button(action: onRowTap) {
            HStack(alignment: .center, spacing: 12) {
                // drawn payment-method glyph — bank rail in a brand vault
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    WalletGlyph(kind: .bank, size: 18, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(method.maskedPAN)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Text(method.spec)
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSettingDefault {
                    ProgressView().scaleEffect(0.7).tint(palette.textTertiary)
                } else {
                    Text(method.tag.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(method.tag == .defaultMethod
                                         ? AnyShapeStyle(LinearGradient.diagonal)
                                         : AnyShapeStyle(palette.textTertiary))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(
                            Capsule().fill(method.tag == .defaultMethod
                                           ? Brand.blue.opacity(0.10)
                                           : palette.textPrimary.opacity(0.04))
                        )
                }
            }
            .padding(.horizontal, Space.s3).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md, intensity: method.tag == .defaultMethod ? .feature : .whisper)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(method.maskedPAN). \(method.spec). \(method.tag.label).")
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// "Add to Wallet" CTA — fires PKAddPassesViewController present
    /// sequence with a .pkpass bundle generated server-side via
    /// wallet.generatePassFor(loadId:). Payload: passId + loadId + carrierMC.
    static let eusoShipperWalletAddPass        = Notification.Name("eusoShipperWalletAddPass")

    /// Per-pass row tap — opens the per-pass edit sheet (lifecycle stage,
    /// pickup window, pass release queue position, scan-history audit).
    /// Tapping the active row re-opens the active pass in Apple Wallet
    /// via the passkit-pass: URL scheme.
    static let eusoShipperWalletPassRow        = Notification.Name("eusoShipperWalletPassRow")

    /// Per-payment-method row tap — opens the per-card edit sheet
    /// (default-card toggle, billing address, expiration, masked PAN
    /// re-tokenization). Default card opens PKPaymentAuthorizationViewController
    /// with the Eusorone merchant id pre-bound.
    static let eusoShipperWalletPaymentMethod  = Notification.Name("eusoShipperWalletPaymentMethod")

    /// "Manage Apple Pay integration" pointer link tap — routes into
    /// 211 Settings's Apple Pay card (source of truth for the per-card
    /// vector + global merchant id binding).
    static let eusoShipperWalletManage         = Notification.Name("eusoShipperWalletManage")
}

// MARK: - Shell wrapper + Shipper BottomNav (Me current)
//
// 2026-05-22 founder ask: every screen's bottom nav must show the
// SAME canonical icons as the home screen (Home / Create Load / Loads /
// Me). The Wallet surface was rendering its own ad-hoc nav that swapped
// the Loads slot for a credit-card icon and replaced "Create Load" with
// nothing — making the bar look like a totally different app the moment
// you opened Apple Pay Wallet. Now routes through the single source of
// truth `shipperLifecycleNav(currentSlot:)` so the icons never change.

struct ShipperApplePayWalletScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ShipperApplePayWallet()
        } nav: {
            shipperLifecycleNav(currentSlot: .me)
        }
    }
}

// MARK: - Previews (Dark + Light per §11.4 doctrine)

#Preview("Shipper Apple Pay Wallet · Dark") {
    ShipperApplePayWalletScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
        .padding(24)
        .background(Theme.dark.bgPage)
}

#Preview("Shipper Apple Pay Wallet · Light") {
    ShipperApplePayWalletScreen(theme: Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
