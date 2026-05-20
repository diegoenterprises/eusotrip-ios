//
//  239_ShipperApplePayWallet.swift
//  EusoTrip iOS — Shipper Apple Pay / PassKit / Wallet authoring
//                 (§35.3 Arc L)
//
//  iOS twin of:
//    /Users/diegousoro/Desktop/EusoTrip 2027 UI Wireframes/02 Shipper/Code/
//    239_ShipperApplePayWallet.swift
//
//  Surface: per-load Wallet pickup-credential pass + per-card Apple Pay
//  authoring. Ninth Arc L brick after 231→232→233→234→235→236→237→238.
//  Hero = active `.pkpass` for the MATRIX-50 row 1 pickup window
//  (LD-260427-A38FB12C7E · Houston→Dallas · MC-306 Gasoline UN1203 ·
//  $1,900). Tapping "Add to Wallet" fires PKAddPassesViewController.
//  Two cards below: passes-in-Wallet (3 rows mapping to MATRIX-50 rows
//  1/2/3) and Apple Pay methods (Visa default + Amex backup, both on
//  the Eusorone Technologies merchant account).
//
//  §11 Diego canon · §11.2/§11.4 MATRIX-50 lane canon all anchored.
//  Doctrine: §2 nav, §3 numbers-first, §4.3 single hairline, §7 breathe
//  density, §17.2 width-locked status grammar, §19.2 file-scoped helpers
//  (GradientPassHeader, GradientCapsuleCTA, DecorativeQRGrid,
//  TierLetterBadge, LDTile, WalletStatusPill, PassRow, PaymentCardRow), §20.4
//  no dead buttons, §22.2 counter eyebrow color encodes screen-status,
//  §35.3 Arc L iOS-platform integration surfaces.
//
//  Backend (server) endpoints owed (EUSO-2160):
//    wallet.listPaymentMethods           -> [PaymentMethod]
//    wallet.generatePassFor(loadId)      -> URL (signed .pkpass)
//    wallet.recordPaymentEvent(loadId, paymentMethodId, amount)
//    wallet.getPassReleaseQueue          -> [QueueEntry]
//
//  iOS API surface (consumed by LiveDataStore):
//    ShipperWalletAPI.currentPasses()           -> [WalletPass]
//    ShipperWalletAPI.generatePass(forLoadId:)  -> Result<URL, Error>
//    ShipperWalletAPI.addToWallet(passUrl:)      -> PKAddPassesViewController
//    ShipperWalletAPI.paymentMethods()           -> [PaymentMethod]
//    ShipperWalletAPI.setDefaultMethod(_:)
//
//  iOS framework binding:
//    PassKit (PKPass / PKPassLibrary / PKAddPassesViewController) +
//    Apple Pay (PKPaymentRequest / PKPaymentAuthorizationViewController).
//    Each .pkpass is signed against the Eusorone PassKit certificate
//    and carries: serialNumber = LD-id, primaryFields = lane,
//    secondaryFields = ETA, auxiliaryFields = carrier + escrow,
//    barcodes[0].message = "eusotrip://load/LD-..." for gate-scanner
//    verification.
//
//  Both #Preview blocks (Dark + Light) ship per §11.4 doctrine.
//

import SwiftUI

// MARK: - Screen

struct ShipperApplePayWallet: View {
    @Environment(\.palette) var palette
    @Environment(\.openURL) private var openURL

    /// Inline QR payload, set when `EusoWalletPassService` falls back
    /// to the no-pkpass branch. The hero pickup card swaps from the
    /// decorative grid to a live `EusoQRView` whenever this is non-nil.
    @State var inlineQrPayload: String? = nil
    /// 5-digit fallback code shown next to the QR for the "type-it"
    /// path when the gate scanner can't read the QR (camera issue,
    /// glare, rooted device with no camera permission).
    @State var inlineShortCode: String? = nil
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

    private var activePassId: String { activePass?.id ?? "" }

    /// Eyebrow counter — recomputes from live state instead of a
    /// hardcoded "3 PASSES · 1 ACTIVE" string. When there are no
    /// passes the screen still reads "0 PASSES · 0 ACTIVE" instead
    /// of lying about installed Wallet bundles.
    private var counterEyebrow: String {
        let activeCount = activePass != nil ? 1 : 0
        return "\(passes.count) PASSES · \(activeCount) ACTIVE"
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, Space.s5)
            titleBlock
                .padding(.top, Space.s3)

            IridescentHairline()
                .padding(.top, Space.s3)

            // ── Active pass hero ───────────────────────────────────
            // Renders the gradient pickup-credential card with QR +
            // Add-to-Wallet CTA when the shipper has a live load.
            // Empty state when none — never a fake hardcoded pass.
            if let pass = activePass {
                sectionLabel(pass.matrixRowLabel ?? "ACTIVE PASS")
                    .padding(.top, Space.s5)
                heroPassCard(for: pass)
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)
            } else if snapshotPhase == .empty {
                sectionLabel("ACTIVE PASS")
                    .padding(.top, Space.s5)
                emptyHeroCard
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)
            } else if snapshotPhase == .loading {
                sectionLabel("ACTIVE PASS")
                    .padding(.top, Space.s5)
                loadingHeroCard
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)
            } else if case .error(let msg) = snapshotPhase {
                sectionLabel("ACTIVE PASS")
                    .padding(.top, Space.s5)
                errorHeroCard(message: msg)
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)
            }

            // ── Pass list ──────────────────────────────────────────
            if !passes.isEmpty {
                sectionLabel("PASSES · \(passes.count) IN WALLET")
                    .padding(.top, Space.s5)
                passesCard
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)
            }

            // ── Apple Pay methods ──────────────────────────────────
            sectionLabel("APPLE PAY · \(paymentMethods.count) METHODS")
                .padding(.top, Space.s5)
            if paymentMethods.isEmpty {
                emptyPaymentMethodsCard
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)
            } else {
                paymentMethodsCard
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)
            }

            settingsPointerLink
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)

            footer
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s5)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    // MARK: — Empty / loading / error hero states

    private var loadingHeroCard: some View {
        VStack(spacing: 10) {
            ProgressView().scaleEffect(0.9).tint(palette.textPrimary)
            Text("Loading your active pickup credential…")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var emptyHeroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wallet.pass")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("No active pickup credential")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Post a load and accept a carrier's bid — we'll mint a signed .pkpass for your gate scanner the moment the load goes in-transit.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "204"])
            } label: {
                GradientCapsuleCTA(label: "Post a load", width: 140)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorHeroCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("Couldn't load wallet").font(.system(size: 14, weight: .heavy)).foregroundStyle(palette.textPrimary)
            }
            Text(message).font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { Task { await loadAll() } } label: {
                Text("Retry")
                    .font(.system(size: 12, weight: .heavy))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(LinearGradient.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var emptyPaymentMethodsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No payment methods on file")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Add a card via Apple Pay or Plaid to fund escrow + accept settlements.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: — Data loading

    @MainActor
    private func loadAll() async {
        snapshotPhase = .loading
        async let snapshot = (try? await EusoTripAPI.shared.wallet.shipperPassesSnapshot())
            ?? WalletAPI.ShipperPassesSnapshot(active: nil, passes: [])
        async let methods = (try? await EusoTripAPI.shared.wallet.listPaymentMethods()) ?? []
        let snap = await snapshot
        let mts = await methods

        passes = snap.passes.map { row in
            WalletPass(
                id: row.id,
                tilePrefix: row.tilePrefix,
                lane: row.lane,
                spec: row.spec,
                installedNote: row.installedNote,
                status: WalletPassStatus.fromServer(row.status)
            )
        }
        activePass = snap.active.map(Self.heroFromRow)
        paymentMethods = mts.map(Self.methodFromRow)
        snapshotPhase = (snap.active == nil && snap.passes.isEmpty) ? .empty : .loaded
    }

    /// Translate a server `ShipperPassRow` into the hero card's
    /// ActiveWalletPass shape. Adds the human-formatted ETA + the
    /// "MATRIX-50" eyebrow (server doesn't know about the cohort).
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

        return ActiveWalletPass(
            id: "pass_\(row.id)",
            issuerLine: "EUSORONE TECHNOLOGIES",
            title: "Pickup Credential",
            loadId: row.id,
            lane: row.lane,
            eta: etaText,
            equipment: equipmentLine.isEmpty ? "Equipment pending" : equipmentLine,
            carrierLine: carrierLine,
            escrowLine: escrowLine,
            carrierTier: String(row.id.suffix(2)).first.map(String.init) ?? "A",
            ctaLabel: "Add to Wallet",
            // Founder ask 2026-05-19 — canonical SVG section label
            // "ACTIVE PASS · MATRIX-50 ROW 1" should show when an
            // active load exists. Default to row 1 when the server
            // doesn't tag a cohort; downstream cohort tagging
            // (server-side metadata.matrix50.row) will flip this.
            matrixRowLabel: "ACTIVE PASS · MATRIX-50 ROW 1"
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

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\u{2726} SHIPPER · WALLET")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel("Three Apple Wallet passes installed. One is currently the active pickup credential.")
        }
        .padding(.horizontal, Space.s5)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Wallet")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Apple Pay · Eusorone Technologies")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s5)
    }

    // MARK: - HERO PASS CARD (active Wallet pass)

    private func heroPassCard(for pass: ActiveWalletPass) -> some View {
        // Local alias so the (large) body below keeps referring to
        // `activePass` exactly as it did when this was a computed
        // var off the @State property. The optional unwrap happens
        // at the call site (`if let pass = activePass`).
        let activePass = pass
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )

            VStack(alignment: .leading, spacing: 0) {
                GradientPassHeader(
                    issuerLine: activePass.issuerLine,
                    title:      activePass.title
                )

                ZStack(alignment: .topLeading) {
                    // SVG-canonical offsets: LOAD ID label y=62 (22pt
                    // below the 40h header strip), LOAD ID value y=80,
                    // LANE label y=102, LANE value y=124, ETA/EQUIPMENT
                    // row y=144. Spacings retuned to those gaps.
                    VStack(alignment: .leading, spacing: 0) {
                        Text("LOAD ID")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, 22)

                        Text(activePass.loadId)
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .tracking(0.4)
                            .foregroundStyle(LinearGradient.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .padding(.top, 4)

                        Text("LANE")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, 14)

                        Text(activePass.lane)
                            .font(.system(size: 20, weight: .heavy))
                            .tracking(-0.3)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .padding(.top, 4)

                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ETA")
                                    .font(.system(size: 8, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(palette.textTertiary)
                                Text(activePass.eta)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                    .monospacedDigit()
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("EQUIPMENT")
                                    .font(.system(size: 8, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(palette.textTertiary)
                                Text(activePass.equipment)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                            }
                        }
                        .padding(.top, 14)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Spacer()
                        // Real QR code via the shared EusoQR primitive.
                        // Encodes a role-aware deeplink to the load
                        // credential, plus the 5-digit fallback code
                        // visible underneath when `inlineShortCode`
                        // is populated. Founder mandate 2026-05-06 —
                        // every QR surface needs to actually work.
                        VStack(alignment: .trailing, spacing: 6) {
                            EusoQRView(
                                kind: .loadCredential(
                                    loadId: activePass.loadId,
                                    mode: .credential
                                ),
                                role: .shipper,
                                size: 92,
                                cornerRadius: 8
                            )
                            if let code = inlineShortCode {
                                Text(code)
                                    .font(EType.mono(.micro)).tracking(2.0)
                                    .foregroundStyle(palette.textPrimary)
                            }
                        }
                        .padding(.top, 12)
                        .padding(.trailing, 20)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                HStack(alignment: .center, spacing: 12) {
                    TierLetterBadge(letter: activePass.carrierTier)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activePass.carrierLine)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text(activePass.escrowLine)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(LinearGradient.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer(minLength: 0)

                    Button(action: tapAddToWallet) {
                        GradientCapsuleCTA(label: activePass.ctaLabel, width: 140)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add the active pickup credential to Apple Wallet — installs a .pkpass bundle bound to \(activePass.loadId).")
                }
                .padding(.horizontal, 20)
                // SVG carrier band sits at y=178 within the 220h card;
                // body content ends near y=160 (ETA value baseline), so
                // the gap is ~18pt. The prior 56pt was driven by the
                // unbounded body and pushed the carrier band off-card.
                .padding(.top, 14)
                .padding(.bottom, 14)
            }
        }
        // SVG-canonical hero pass-card height — 220pt fixed. Locking
        // minHeight = maxHeight so the gradient header strip (40) +
        // body block (140) + carrier band (40) total exactly to the
        // spec and the QR + Add-to-Wallet pill sit in their
        // SVG-defined positions instead of drifting on long strings.
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var passesCard: some View {
        VStack(spacing: 0) {
            ForEach(passes.indices, id: \.self) { idx in
                PassRow(
                    pass:        passes[idx],
                    isActive:    passes[idx].id == activePassId,
                    onRowTap:    { tapPassRow(passes[idx]) }
                )
                if idx < passes.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var paymentMethodsCard: some View {
        VStack(spacing: 0) {
            ForEach(paymentMethods.indices, id: \.self) { idx in
                PaymentCardRow(
                    method:    paymentMethods[idx],
                    onRowTap:  { tapPaymentMethod(paymentMethods[idx]) }
                )
                if idx < paymentMethods.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var settingsPointerLink: some View {
        Button(action: tapManageApplePay) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage Apple Pay integration")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Per-card · per-pass settings · 211 Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\u{2192}")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Manage Apple Pay integration. Per-card and per-pass settings live in 211 Settings.")
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Powered by Apple Pay · PassKit · Wallet")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
            Text("companyId 1 · Eusorone Technologies · MATRIX-50-2026-04-26")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, Space.s5)
    }

    // MARK: - Tap handlers (§20.4 no dead buttons)

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
                "loadId": pass.loadId,
                "carrierLine": pass.carrierLine,
            ]
        )
        // Hand off to PassKit. The service handles the
        //   server credential mint → .pkpass fetch → PKPass parse →
        //   PKAddPassesViewController present
        // chain, plus a graceful fallback to the inline QR + 5-digit
        // shortCode card when the .pkpass signing pipeline is offline.
        let loadId = pass.loadId
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
                "loadId": pass.id,
                "isActivePass": pass.id == activePassId,
                "shipperCompanyId": 1
            ]
        )
        // Tapping any pass row in the list also routes to the same
        // PassKit flow — every pass should add to Apple Wallet, not
        // open Safari.
        let loadId = pass.id
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
        switch result {
        case .presented:
            passBannerKind = .success
            passBannerText = "Pass added to Apple Wallet"
        case .signingUnavailable(let qrPayload, let shortCode):
            passBannerKind = .info
            passBannerText = "Wallet signing offline — show the in-app QR + code \(shortCode) at the gate."
            inlineQrPayload = qrPayload
            inlineShortCode = shortCode
        case .failure(let message):
            passBannerKind = .error
            passBannerText = message
        }
        // Auto-clear after 4s so the banner doesn't linger.
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
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
                        PaymentMethod(
                            id: $0.id,
                            brand: $0.brand,
                            maskedPAN: $0.maskedPAN,
                            spec: $0.spec.replacingOccurrences(of: " · default ·", with: " · backup ·")
                                       .replacingOccurrences(of: " · backup ·", with: $0.id == method.id ? " · default ·" : " · backup ·"),
                            tag: $0.id == method.id ? .defaultMethod : .backup
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

    /// Tapping the footer routes natively to 211 Settings via the
    /// shipper nav-swap notification. No more web-Safari hop — the
    /// per-card / per-pass controls live in the native settings
    /// surface that's already on screen 211.
    private func tapManageApplePay() {
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap,
            object: nil,
            userInfo: [
                "screenId": "211",
                "source": "239_ShipperApplePayWallet",
                "deeplinkSection": "wallet",
            ]
        )
    }
}

// MARK: - Domain models (file-scoped — wired by LiveDataStore from
//          ShipperWalletAPI.currentPasses() + wallet.listPaymentMethods)

private struct ActiveWalletPass {
    let id:          String
    let issuerLine:  String
    let title:       String
    let loadId:      String
    let lane:        String
    let eta:         String
    let equipment:   String
    let carrierLine: String
    let escrowLine:  String
    let carrierTier: String
    let ctaLabel:    String
    /// Optional eyebrow ("ACTIVE PASS · MATRIX-50 ROW 1" etc.). nil
    /// when the server didn't tag the load with a cohort label.
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

    var pillWidth: CGFloat {
        switch self {
        case .active:    return 60
        case .inTransit: return 78
        case .escort:    return 60
        case .pending:   return 68
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
    let id:            String
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

// MARK: - GradientPassHeader (40pt Apple Wallet pass-issuer header strip
//          — gradient diagonal fill, white issuer line + title + Apple
//          Pay "Pay" capsule on the right)

private struct GradientPassHeader: View {
    let issuerLine: String
    let title:      String

    var body: some View {
        ZStack(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius:     Radius.lg,
                bottomLeadingRadius:  0,
                bottomTrailingRadius: 0,
                topTrailingRadius:    Radius.lg,
                style: .continuous
            )
            .fill(LinearGradient.diagonal)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(issuerLine)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(Color.white.opacity(0.85))
                    Text(title)
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.3)
                        .foregroundStyle(.white)
                }
                Spacer()
                ZStack {
                    Capsule().fill(Color.white.opacity(0.18))
                    Text("Pay")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(issuerLine) — \(title) — Apple Pay")
    }
}

// MARK: - GradientCapsuleCTA (140×22 hero CTA — 234/235/236/237/238 recipe)

private struct GradientCapsuleCTA: View {
    let label: String
    let width: CGFloat

    var body: some View {
        ZStack {
            Capsule().fill(LinearGradient.primary)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 8)
        }
        .frame(width: width, height: 22)
    }
}

// MARK: - DecorativeQRGrid (90×90 pseudo-QR with 3 position markers +
//          module pattern. Decorative — production renders a real QR
//          via CIQRCodeGenerator from "eusotrip://load/LD-...")

private struct DecorativeQRGrid: View {
    @Environment(\.palette) var palette

    private let modules: [(CGFloat, CGFloat)] = [
        (32,6),(38,6),(44,6),(56,6),
        (32,12),(50,12),(56,12),
        (38,18),(44,18),(56,18),
        (32,24),(44,24),(50,24),
        (6,32),(18,32),(32,32),(44,32),(56,32),(68,32),(80,32),
        (12,38),(24,38),(38,38),(50,38),(62,38),(74,38),
        (6,44),(18,44),(32,44),(44,44),(56,44),(68,44),(80,44),
        (12,50),(24,50),(38,50),(50,50),(62,50),(74,50),
        (32,56),(44,56),(56,56),(68,56),(80,56),
        (38,64),(50,64),(62,64),(74,64),
        (32,70),(50,70),(56,70),(68,70),(80,70),
        (38,76),(44,76),(62,76),(74,76),
        (32,82),(44,82),(56,82),(68,82),(80,82)
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white)

            positionMarker(at: CGPoint(x: 6, y: 6))
            positionMarker(at: CGPoint(x: 64, y: 6))
            positionMarker(at: CGPoint(x: 6, y: 64))

            ForEach(modules.indices, id: \.self) { idx in
                let p = modules[idx]
                Rectangle()
                    .fill(Color(red: 0.05, green: 0.07, blue: 0.09))
                    .frame(width: 3, height: 3)
                    .offset(x: p.0, y: p.1)
            }
        }
        .frame(width: 90, height: 90)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func positionMarker(at p: CGPoint) -> some View {
        let mark = Color(red: 0.05, green: 0.07, blue: 0.09)
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(mark)
                .frame(width: 20, height: 20)
            Rectangle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .offset(x: 3, y: 3)
            Rectangle()
                .fill(mark)
                .frame(width: 8, height: 8)
                .offset(x: 6, y: 6)
        }
        .offset(x: p.x, y: p.y)
    }
}

// MARK: - TierLetterBadge (24×24 — 233 catalyst-grade recipe at
//          compact pass-band scale)

private struct TierLetterBadge: View {
    let letter: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient.primary)
            Text(letter)
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel("Catalyst tier \(letter)")
    }
}

// MARK: - LDTile (36×36 — 237/238 InitialsTile recipe, semantic pivot to
//          "active pass")

private struct LDTile: View {
    @Environment(\.palette) var palette
    let prefix: String
    let active: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(active
                      ? AnyShapeStyle(LinearGradient.primary)
                      : AnyShapeStyle(palette.textPrimary.opacity(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(active
                                      ? Color.clear
                                      : palette.borderFaint)
                )
            Text(prefix)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(active
                                 ? AnyShapeStyle(Color.white)
                                 : AnyShapeStyle(palette.textTertiary))
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

// MARK: - WalletStatusPill (60×18 gradient or 78×18 outlined — per-pass status)

private struct WalletStatusPill: View {
    @Environment(\.palette) var palette
    let status: WalletPassStatus

    var body: some View {
        ZStack {
            if status == .active {
                Capsule().fill(LinearGradient.primary)
            } else {
                Capsule()
                    .strokeBorder(palette.textPrimary.opacity(0.20),
                                  lineWidth: 1)
            }
            Text(status.label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(status == .active
                                 ? AnyShapeStyle(Color.white)
                                 : AnyShapeStyle(palette.textSecondary))
        }
        .frame(width: status.pillWidth, height: 18)
    }
}

// MARK: - PassRow (per-pass row — LD-tile + lane + italic spec + mono
//          LD-id + status pill; active variant gets gradient wash)

private struct PassRow: View {
    @Environment(\.palette) var palette
    let pass:        WalletPass
    let isActive:    Bool
    let onRowTap:    () -> Void

    var body: some View {
        Button(action: onRowTap) {
            ZStack(alignment: .leading) {
                if isActive {
                    LinearGradient.primary
                        .opacity(0.12)
                }

                HStack(alignment: .center, spacing: 12) {
                    if isActive {
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: 6, height: 6)
                            .padding(.leading, 4)
                    } else {
                        Color.clear.frame(width: 10, height: 6)
                    }

                    LDTile(prefix: pass.tilePrefix, active: isActive)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pass.lane)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(isActive
                                             ? AnyShapeStyle(LinearGradient.primary)
                                             : AnyShapeStyle(palette.textPrimary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(pass.spec)
                            .font(.system(size: 10).italic())
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text("\(pass.id) · \(pass.installedNote)")
                            .font(EType.mono(.micro))
                            .tracking(0.3)
                            .foregroundStyle(isActive
                                             ? AnyShapeStyle(LinearGradient.primary)
                                             : AnyShapeStyle(palette.textTertiary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    WalletStatusPill(status: pass.status)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(pass.lane). \(pass.spec). \(pass.id), \(pass.installedNote). Status \(pass.status.label).\(isActive ? " Active pickup credential." : "")")
    }
}

// MARK: - PaymentCardRow (per-payment-method row · 32×20 card glyph +
//          masked PAN + textSecondary spec + status tag — mirrors 208's
//          larger PaymentMethod row recipe at compact-row scale)

private struct PaymentCardRow: View {
    @Environment(\.palette) var palette
    let method:    PaymentMethod
    let onRowTap:  () -> Void

    var body: some View {
        Button(action: onRowTap) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(red: 0.05, green: 0.07, blue: 0.09))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(palette.borderFaint, lineWidth: 1)
                        )
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.white.opacity(0.40))
                            .frame(height: 3)
                            .padding(.top, 5)
                        Spacer(minLength: 0)
                    }
                    Text(method.brand.rawValue)
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.top, 6)
                }
                .frame(width: 32, height: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(method.maskedPAN)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(method.spec)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(method.tag.label)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(method.tag == .defaultMethod
                                     ? AnyShapeStyle(LinearGradient.primary)
                                     : AnyShapeStyle(palette.textTertiary))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
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

private func shipperNavLeading() -> [NavSlot] {
    [
        NavSlot(label: "Home",  systemImage: "house.fill",   isCurrent: false),
        NavSlot(label: "Loads", systemImage: "shippingbox",  isCurrent: false),
    ]
}
private func shipperNavTrailing() -> [NavSlot] {
    [
        NavSlot(label: "My Loads", systemImage: "creditcard",   isCurrent: false),
        NavSlot(label: "Me",     systemImage: "person.fill",  isCurrent: true),
    ]
}

struct ShipperApplePayWalletScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ShipperApplePayWallet()
        } nav: {
            BottomNav(leading: shipperNavLeading(),
                      trailing: shipperNavTrailing(),
                      orbState: .idle)
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
        .padding(24)
        .background(Theme.light.bgPage)
}
