//
//  208_ShipperPaymentMethods.swift
//  EusoTrip — Shipper · Payment Methods (brick 208).
//
//  Parity-reconciled to `02 Shipper/Code/208_ShipperPaymentMethods.swift`
//  per _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: TopBar (eyebrow + on-file counter), title block (display +
//  ACH/card/EusoWallet sub-line), IridescentHairline, DEFAULT METHOD
//  section with 400×180 gradient hero credit card (EMV chip +
//  contactless + Mastercard mark + masked number + holder + expiry),
//  ALL METHODS card (rows + dashed Add CTA inside same chrome),
//  AUTO-PAY RULES card (catalyst auto-pay 24h + hazmat pre-funded).
//
//  Real data preserved: PaymentMethodsStore +
//  payments.{getPaymentMethods, setDefaultMethod, deletePaymentMethod}
//  + AddPaymentAccountSheet + alert + toast — all unchanged. Hero
//  card hydrates from the live default method when present, falls
//  back to §11 Diego Usoro canon.
//
//  Persona canon (§11): Diego Usoro · Eusorone Technologies (companyId 1).
//  §11 hero-card canon: Mastercard ending 4821, holder DIEGO USORO,
//  expires 09/28. §11.2 hazmat auto-pay UN trio: UN1203 + UN1005.
//
//  Web peer: PaymentMethods.tsx (`/wallet/payment-methods`).
//  Notification names: eusoShipperPaymentDefaultCard,
//                      eusoShipperPaymentMethodTap,
//                      eusoShipperPaymentAddMethod,
//                      eusoShipperPaymentAutoPayToggle.
//
//  BottomNav: Wallet current — out of scope per parity mandate §1.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Visual taxonomy

private enum PaymentRowStatus {
    case defaultMethod   // gradient pill DEFAULT
    case verified        // success-tint pill VERIFIED
    case primary         // gradient pill PRIMARY (EusoWallet)
}

// MARK: - Screen body

struct ShipperPaymentMethods: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var store = PaymentMethodsStore()

    @State private var showAddSheet: Bool = false
    @State private var pendingUnlink: PaymentsAPI.PaymentMethod?
    @State private var lastToast: String?

    /// Auto-pay rules — local toggles until payments.{getAutoPayRules,
    /// setAutoPayRule} ships. State is preserved across the screen but
    /// not persisted; toggle posts the canonical notification so a
    /// future server handler can hydrate.
    @State private var catalystAutoPayEnabled: Bool = true
    @State private var hazmatPrefundEnabled:  Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            titleBlock
                .padding(.top, Space.s3)
            IridescentHairline()
                .padding(.top, Space.s3)
                .padding(.horizontal, Space.s5)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    sectionLabel("DEFAULT METHOD")
                    heroCardView
                    sectionLabel("ALL METHODS")
                    methodsCard
                    sectionLabel("AUTO-PAY RULES")
                    autoPayCard
                    disclosureFooter
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
            .overlay(alignment: .bottom) {
                if let toast = lastToast {
                    toastView(toast)
                        .padding(.bottom, Space.s5)
                        .padding(.horizontal, Space.s5)
                        .transition(.opacity)
                }
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $showAddSheet, onDismiss: {
            Task { await store.refresh() }
        }) {
            AddPaymentAccountSheet(onLinked: {
                showAddSheet = false
                Task { await store.refresh() }
            })
            .eusoSheetX()
        }
        .alert(
            pendingUnlink.map { $0.type == "card" ? "Unlink card?" : "Unlink bank?" } ?? "Unlink?",
            isPresented: Binding(
                get: { pendingUnlink != nil },
                set: { if !$0 { pendingUnlink = nil } }
            ),
            presenting: pendingUnlink
        ) { row in
            Button("Unlink", role: .destructive) {
                Task {
                    await store.unlink(id: row.id)
                    flashToast("Method unlinked")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { row in
            if row.type == "card" {
                Text("This removes \(row.brand ?? "the card") ••\(row.last4). Future load checkouts will fall back to your default bank.")
            } else {
                Text("This removes \(row.bankName ?? "the bank") ••\(row.last4). Load funding will pause until you pick another default.")
            }
        }
    }

    // MARK: - TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · WALLET · PAYMENT METHODS")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1).minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    private var counterEyebrow: String {
        let count = liveRows.count
        return count > 0 ? "\(count) ON FILE · STRIPE" : "0 ON FILE · STRIPE"
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Payment methods")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · ACH + card + EusoWallet")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro).tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hero credit card (400×180 gradient, hydrates from default)

    private var liveRows: [PaymentsAPI.PaymentMethod] {
        if case .loaded(let rows) = store.state { return rows }
        return []
    }

    private var defaultCardRow: PaymentsAPI.PaymentMethod? {
        liveRows.first(where: { $0.isDefault && $0.type == "card" })
            ?? liveRows.first(where: { $0.type == "card" })
    }

    private var heroMaskedNumber: String {
        if let r = defaultCardRow { return "···· ···· ···· \(r.last4)" }
        return "···· ···· ···· 4821"
    }

    private var heroHolder: String {
        let name = session.user?.name ?? "Diego Usoro"
        return name.uppercased()
    }

    private var heroExpiry: String {
        defaultCardRow?.expiryDate ?? "09 / 28"
    }

    private var heroBrand: String {
        defaultCardRow?.brand?.capitalized ?? "Mastercard"
    }

    private var heroCardView: some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoShipperPaymentDefaultCard, object: nil,
                userInfo: [
                    "source": "208_ShipperPaymentMethods",
                    "shipperCompanyId": session.user?.companyId ?? "1",
                    "methodId": defaultCardRow?.id ?? "card_4821",
                ]
            )
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.blue, Brand.magenta],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .overlay(alignment: .topLeading) {
                        Ellipse()
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 320, height: 80)
                            .offset(x: -80, y: -20)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 14) {
                        EmvChipGlyph().frame(width: 44, height: 32)
                        ContactlessGlyph().frame(width: 22, height: 22).padding(.top, 4)
                        Spacer()
                        NetworkMarkGlyph().frame(width: 44, height: 28).padding(.top, 4)
                    }
                    .padding(.top, 28)
                    .padding(.horizontal, 28)

                    Spacer()

                    Text(heroMaskedNumber)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .tracking(2.0)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("HOLDER")
                                .font(EType.micro).tracking(1.0)
                                .foregroundStyle(Color.white.opacity(0.7))
                            Text(heroHolder)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.85)
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("EXP")
                                .font(EType.micro).tracking(1.0)
                                .foregroundStyle(Color.white.opacity(0.7))
                            Text(heroExpiry)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: 80, alignment: .leading)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .padding(.bottom, 22)
                }
            }
            .frame(height: 180)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Default payment method, \(heroBrand) ending in \(defaultCardRow?.last4 ?? "4821"), holder \(heroHolder), expires \(heroExpiry).")
        .accessibilityHint("Opens the card-detail sheet.")
    }

    // MARK: - All methods card

    private var methodsCard: some View {
        VStack(spacing: 0) {
            switch store.state {
            case .loading:
                methodsSkeleton
                    .padding(.horizontal, 20).padding(.vertical, 14)
            case .loaded(let rows):
                if rows.isEmpty {
                    emptyMethodsContent
                        .padding(.horizontal, 20).padding(.vertical, 18)
                } else {
                    let allMethods = methodsList(rows)
                    ForEach(allMethods.indices, id: \.self) { idx in
                        methodRow(allMethods[idx])
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        if idx < allMethods.count - 1 {
                            Rectangle()
                                .fill(palette.borderFaint)
                                .frame(height: 1)
                                .padding(.horizontal, 20)
                        }
                    }
                }
            case .empty:
                emptyMethodsContent
                    .padding(.horizontal, 20).padding(.vertical, 18)
            case .error(let err):
                errorContent(err)
                    .padding(.horizontal, 20).padding(.vertical, 18)
            }
            // Dashed Add row sits inside the same card chrome
            addMethodRow
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Sort: default card first, then verified banks, then everything else
    /// (which surfaces the EusoWallet-style PRIMARY when it lands in the
    /// envelope; today the server returns card+bank only).
    private func methodsList(_ rows: [PaymentsAPI.PaymentMethod]) -> [PaymentsAPI.PaymentMethod] {
        rows.sorted { l, r in
            if l.isDefault != r.isDefault { return l.isDefault }
            if l.type != r.type { return l.type < r.type }
            return l.last4 < r.last4
        }
    }

    private func methodRow(_ row: PaymentsAPI.PaymentMethod) -> some View {
        let isMutating = store.mutatingId == row.id
        let status: PaymentRowStatus = row.isDefault ? .defaultMethod : .verified
        return Button {
            NotificationCenter.default.post(
                name: .eusoShipperPaymentMethodTap, object: nil,
                userInfo: [
                    "source": "208_ShipperPaymentMethods",
                    "shipperCompanyId": session.user?.companyId ?? "1",
                    "methodId": row.id,
                    "kind": row.type,
                    "isDefault": row.isDefault,
                ]
            )
        } label: {
            HStack(alignment: .center, spacing: 16) {
                methodIcon(for: row)
                    .frame(width: 40, height: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(rowTitle(row))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Text(rowSubtitle(row))
                        .font(.system(size: 11, design: row.type == "bank" ? .monospaced : .default))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isMutating {
                    ProgressView().progressViewStyle(.circular).controlSize(.small)
                        .frame(width: 80, height: 22)
                } else if row.isDefault {
                    statusPill(status)
                        .frame(width: 80, height: 22)
                } else {
                    Menu {
                        Button {
                            Task {
                                await store.setDefault(id: row.id)
                                flashToast("Funding default updated")
                            }
                        } label: {
                            Label("Set as default", systemImage: "star")
                        }
                        Button(role: .destructive) {
                            pendingUnlink = row
                        } label: {
                            Label("Unlink", systemImage: "trash")
                        }
                    } label: {
                        statusPill(status)
                            .frame(width: 80, height: 22)
                    }
                    .menuStyle(.button)
                    .accessibilityLabel("Manage \(rowTitle(row))")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rowTitle(row)). \(rowSubtitle(row)).")
    }

    @ViewBuilder
    private func methodIcon(for row: PaymentsAPI.PaymentMethod) -> some View {
        if row.type == "card" {
            MiniCardChip(last4: row.last4)
        } else {
            BankBuildingGlyph(stroke: palette.textPrimary)
        }
    }

    private func statusPill(_ status: PaymentRowStatus) -> some View {
        ZStack {
            switch status {
            case .defaultMethod, .primary:
                Capsule().fill(LinearGradient.primary)
            case .verified:
                Capsule().fill(Brand.success.opacity(0.10))
            }
            Text(label(for: status))
                .font(.system(size: 10, weight: .bold)).tracking(0.4)
                .foregroundStyle(textColor(for: status))
        }
    }

    private func label(for status: PaymentRowStatus) -> String {
        switch status {
        case .defaultMethod: return "DEFAULT"
        case .verified:      return "VERIFIED"
        case .primary:       return "PRIMARY"
        }
    }
    private func textColor(for status: PaymentRowStatus) -> Color {
        switch status {
        case .defaultMethod, .primary: return .white
        case .verified:                return Brand.success
        }
    }

    // Dashed Add-method row (lives inside the methods card chrome)
    private var addMethodRow: some View {
        Button {
            showAddSheet = true
            NotificationCenter.default.post(
                name: .eusoShipperPaymentAddMethod, object: nil,
                userInfo: [
                    "source": "208_ShipperPaymentMethods",
                    "shipperCompanyId": session.user?.companyId ?? "1",
                ]
            )
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.blue.opacity(0.06), Brand.magenta.opacity(0.06)],
                                         startPoint: .leading, endPoint: .trailing))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(LinearGradient.primary.opacity(0.30),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                HStack(spacing: 8) {
                    PlusGlyph().frame(width: 14, height: 14)
                    Text("Add card · ACH · or wire")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LinearGradient.primary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            .frame(height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add new payment method")
        .accessibilityHint("Opens the credential-ingest flow for card, ACH bank account, or wire transfer.")
    }

    // MARK: - Auto-pay rules card

    private var autoPayCard: some View {
        VStack(spacing: 0) {
            autoPayRow(
                id: "catalyst_24h",
                title: "Catalyst settlements · auto-pay 24h",
                sub: "From EusoWallet · all delivered loads · BOL signed",
                isOn: $catalystAutoPayEnabled
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 20)
            autoPayRow(
                id: "hazmat_prefund",
                title: "Hazmat surcharge · pre-funded",
                sub: "UN1203 + UN1005 lanes · escrow released on delivery",
                isOn: $hazmatPrefundEnabled
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func autoPayRow(id: String, title: String, sub: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                let wasOn = isOn.wrappedValue
                isOn.wrappedValue.toggle()
                NotificationCenter.default.post(
                    name: .eusoShipperPaymentAutoPayToggle, object: nil,
                    userInfo: [
                        "source": "208_ShipperPaymentMethods",
                        "shipperCompanyId": session.user?.companyId ?? "1",
                        "ruleId": id,
                        "wasOn": wasOn,
                    ]
                )
            } label: {
                ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn.wrappedValue
                              ? AnyShapeStyle(LinearGradient.primary)
                              : AnyShapeStyle(palette.textPrimary.opacity(0.10)))
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .padding(.horizontal, 3)
                }
                .frame(width: 44, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(isOn.wrappedValue ? "on" : "off")")
        }
    }

    // MARK: - Empty / loading / error / disclosure

    private var methodsSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 56)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint))
            }
        }
    }

    private var emptyMethodsContent: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("No methods yet")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("Link a bank through Plaid for ACH funding, or attach a card via Stripe. Credentials live at Stripe and Plaid — never on EusoTrip's servers.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorContent(_ err: Error) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Brand.danger)
                Text("Couldn't load methods")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text(err.localizedDescription)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("Processed by Stripe + Plaid")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("EusoTrip never stores your bank or card credentials — they live at Stripe and Plaid, both independently certified. Your default method funds load checkout when you accept a carrier bid; ACH banks generally clear in 1–3 business days, cards clear instantly.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCard.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1))
    }

    // MARK: - Toast

    private func toastView(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LinearGradient.diagonal)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.2), radius: 16, y: 8)
    }

    private func flashToast(_ text: String) {
        withAnimation { lastToast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { withAnimation { lastToast = nil } }
        }
    }

    // MARK: - Row formatters

    private func rowTitle(_ row: PaymentsAPI.PaymentMethod) -> String {
        if row.type == "card" {
            let brand = row.brand?.capitalized ?? "Card"
            return "\(brand) ending \(row.last4)"
        } else {
            return "\(row.bankName ?? "Bank") · ···· \(row.last4)"
        }
    }

    private func rowSubtitle(_ row: PaymentsAPI.PaymentMethod) -> String {
        if row.type == "card" {
            let holder = session.user?.name ?? "Diego Usoro"
            if let exp = row.expiryDate { return "\(holder) · expires \(exp)" }
            return "\(holder) · card on file"
        }
        return "ACH · verified"
    }
}

// MARK: - SVG glyph shapes (lifted verbatim from wireframe Code/ port)

private struct EmvChipGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 44, geo.size.height / 32)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                    .fill(Color(hex: 0xFFD080))
                    .frame(width: 44 * s, height: 32 * s)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 10 * s))
                    p.addLine(to: CGPoint(x: 44 * s, y: 10 * s))
                    p.move(to: CGPoint(x: 0, y: 22 * s))
                    p.addLine(to: CGPoint(x: 44 * s, y: 22 * s))
                    p.move(to: CGPoint(x: 14 * s, y: 0))
                    p.addLine(to: CGPoint(x: 14 * s, y: 32 * s))
                    p.move(to: CGPoint(x: 30 * s, y: 0))
                    p.addLine(to: CGPoint(x: 30 * s, y: 32 * s))
                }
                .stroke(Color(hex: 0xB07F0E), lineWidth: 0.8)
            }
        }
    }
}

private struct ContactlessGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 22, geo.size.height / 22)
            Path { p in
                p.move(to: CGPoint(x: 6 * s, y: 8 * s))
                p.addQuadCurve(to: CGPoint(x: 14 * s, y: 8 * s),
                               control: CGPoint(x: 10 * s, y: 4 * s))
                p.move(to: CGPoint(x: 4 * s, y: 12 * s))
                p.addQuadCurve(to: CGPoint(x: 18 * s, y: 12 * s),
                               control: CGPoint(x: 11 * s, y: 4 * s))
                p.move(to: CGPoint(x: 2 * s, y: 16 * s))
                p.addQuadCurve(to: CGPoint(x: 20 * s, y: 16 * s),
                               control: CGPoint(x: 11 * s, y: 4 * s))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

private struct NetworkMarkGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 44, geo.size.height / 28)
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(Color(hex: 0xEB001B).opacity(0.85))
                    .frame(width: 28 * s, height: 28 * s)
                Circle()
                    .fill(Color(hex: 0xF79E1B).opacity(0.85))
                    .frame(width: 28 * s, height: 28 * s)
                    .offset(x: 16 * s, y: 0)
            }
        }
    }
}

private struct MiniCardChip: View {
    let last4: String
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 40, geo.size.height / 28)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                    .fill(LinearGradient.diagonal)
                    .frame(width: 40 * s, height: 28 * s)
                VStack(alignment: .leading, spacing: 0) {
                    Text("··")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.top, 2 * s)
                    Text(last4)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 6 * s)
            }
        }
    }
}

private struct BankBuildingGlyph: View {
    let stroke: Color
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 28, geo.size.height / 26)
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 14 * s, y: 0))
                    p.addLine(to: CGPoint(x: 28 * s, y: 7 * s))
                    p.addLine(to: CGPoint(x: 0, y: 7 * s))
                    p.closeSubpath()
                }
                .fill(stroke)
                Path { p in
                    p.move(to: CGPoint(x: 2 * s, y: 10 * s))
                    p.addLine(to: CGPoint(x: 2 * s, y: 22 * s))
                    p.move(to: CGPoint(x: 10 * s, y: 10 * s))
                    p.addLine(to: CGPoint(x: 10 * s, y: 22 * s))
                    p.move(to: CGPoint(x: 18 * s, y: 10 * s))
                    p.addLine(to: CGPoint(x: 18 * s, y: 22 * s))
                    p.move(to: CGPoint(x: 26 * s, y: 10 * s))
                    p.addLine(to: CGPoint(x: 26 * s, y: 22 * s))
                }
                .stroke(stroke, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 24 * s))
                    p.addLine(to: CGPoint(x: 28 * s, y: 24 * s))
                }
                .stroke(stroke, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }
}

private struct PlusGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 14, geo.size.height / 14)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 7 * s))
                p.addLine(to: CGPoint(x: 14 * s, y: 7 * s))
                p.move(to: CGPoint(x: 7 * s, y: 0))
                p.addLine(to: CGPoint(x: 7 * s, y: 14 * s))
            }
            .stroke(LinearGradient.primary,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let eusoShipperPaymentDefaultCard   = Notification.Name("eusoShipperPaymentDefaultCard")
    static let eusoShipperPaymentMethodTap     = Notification.Name("eusoShipperPaymentMethodTap")
    static let eusoShipperPaymentAddMethod     = Notification.Name("eusoShipperPaymentAddMethod")
    static let eusoShipperPaymentAutoPayToggle = Notification.Name("eusoShipperPaymentAutoPayToggle")
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct ShipperPaymentMethodsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperPaymentMethods()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_208(),
                trailing: shipperNavTrailing_208(),
                orbState: .idle
            )
        }
    }
}

// Out of scope per parity mandate §1.
private func shipperNavLeading_208() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",    isCurrent: false)]
}

private func shipperNavTrailing_208() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.fill",      isCurrent: true)]
}

// MARK: - Previews

#Preview("208 · Shipper · Payment Methods · Night") {
    ShipperPaymentMethodsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("208 · Shipper · Payment Methods · Afternoon") {
    ShipperPaymentMethodsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
