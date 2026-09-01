//
//  PricedRouteQuoteAuthorityPanel.swift
//  EusoTrip
//
//  Formula-free presentation of one immutable server-owned priced route.
//

import SwiftUI

struct PricedRouteQuoteAuthorityPanel: View {
    let subjectType: PricedRouteCommerceClient.SubjectType
    let subjectId: Int
    var allowsPricing: Bool = true

    @Environment(\.palette) private var palette
    @State private var quote: PricedRouteCommerceClient.Quote?
    @State private var loading = true
    @State private var pricing = false
    @State private var errorMessage: String?

    private let client = PricedRouteCommerceClient.shared

    var body: some View {
        LifecycleCard(accentGradient: quote?.isExecutable == true) {
            VStack(alignment: .leading, spacing: Space.s3) {
                heading

                if loading && quote == nil {
                    HStack(spacing: Space.s2) {
                        ProgressView().controlSize(.small)
                        Text("Reading immutable quote…")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                } else if let quote {
                    quoteBody(quote)
                } else {
                    Text("No immutable priced-route version is recorded for this work yet.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if allowsPricing {
                    priceButton
                }
            }
        }
        .task { await readCurrent() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Immutable priced route")
    }

    private var heading: some View {
        HStack(spacing: Space.s2) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 34, height: 34)
                Image(systemName: modeIcon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("PRICED ROUTE · VERIFIED TERMS")
                    .font(EType.micro.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Route, capacity, fees, and payouts — one version")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s2)
            if let quote {
                Text(quote.isExecutable ? "PRICED" : "PENDING")
                    .font(EType.micro.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(quote.isExecutable ? Brand.success : Brand.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((quote.isExecutable ? Brand.success : Brand.warning).opacity(0.10))
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private func quoteBody(_ quote: PricedRouteCommerceClient.Quote) -> some View {
        if quote.isExecutable, let totals = quote.totals,
           let currency = quote.currency, let scale = quote.currencyScale {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CUSTOMER TOTAL")
                        .font(EType.micro.weight(.heavy))
                        .tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                    Text(money(totals.customerTotalMinor, currency: currency, scale: scale))
                        .font(EType.h1.monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PLATFORM FEE")
                        .font(EType.micro.weight(.heavy))
                        .tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                    Text(money(totals.platformFeeMinor, currency: currency, scale: scale))
                        .font(EType.bodyStrong.monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                }
            }

            HStack(spacing: Space.s2) {
                metric("SERVICE", money(totals.serviceRevenueMinor, currency: currency, scale: scale))
                metric("CARRIER", money(totals.carrierPayoutMinor, currency: currency, scale: scale))
                metric("DRIVER", money(totals.driverPayoutMinor, currency: currency, scale: scale))
            }

            if !quote.movementLegs.isEmpty {
                Divider().overlay(palette.borderFaint)
                Text("CANONICAL MOVEMENTS")
                    .font(EType.micro.weight(.heavy))
                    .tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                ForEach(quote.movementLegs) { leg in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Circle()
                            .fill(leg.revenueClassification == "revenue" ? Brand.success : Brand.blue)
                            .frame(width: 7, height: 7)
                        Text(movementLabel(leg.movementKind))
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                        Spacer(minLength: Space.s2)
                        Text(distance(leg.distanceMeters, mode: quote.mode))
                            .font(EType.caption.monospacedDigit())
                            .foregroundStyle(palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if !quote.lineItems.isEmpty {
                Divider().overlay(palette.borderFaint)
                Text("IMMUTABLE LINE ITEMS")
                    .font(EType.micro.weight(.heavy))
                    .tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                ForEach(quote.lineItems) { item in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(item.code)
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text(item.category.replacingOccurrences(of: "_", with: " "))
                            .font(EType.micro)
                            .foregroundStyle(palette.textTertiary)
                        Spacer(minLength: Space.s2)
                        Text(money(item.amountMinor, currency: currency, scale: scale))
                            .font(EType.caption.monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }

            authorityReceipt(quote)
        } else {
            if !quote.blockers.isEmpty {
                Text("RELEASE BLOCKERS")
                    .font(EType.micro.weight(.heavy))
                    .tracking(0.7)
                    .foregroundStyle(Brand.warning)
                ForEach(quote.blockers) { blocker in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(blocker.message)
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text(blocker.recovery)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            authorityReceipt(quote)
        }
    }

    private func authorityReceipt(_ quote: PricedRouteCommerceClient.Quote) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("QUOTE V\(quote.version) · \(shortHash(quote.evidenceHashSha256))")
                .font(EType.micro.weight(.heavy))
                .tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            if let route = quote.route {
                Text("ROUTE V\(route.routePlanVersion) · \(shortHash(route.planChecksumSha256)) · GRAPH \(route.graphVersionId)")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
            }
            if let availability = quote.availability {
                Text("\(availability.assetIdentityKey.uppercased()) · ALLOCATION V\(availability.allocationVersion) · \(shortHash(availability.allocationHashSha256))")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var priceButton: some View {
        Button {
            Task { await createPrice() }
        } label: {
            HStack(spacing: Space.s2) {
                if pricing {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up.fill")
                }
                Text(quote == nil ? "Price exact route" : "Create new price version")
                Spacer()
                Image(systemName: "lock.shield.fill")
            }
            .font(EType.bodyStrong)
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(pricing || subject == nil)
        .opacity(subject == nil ? 0.55 : 1)
        .accessibilityHint("Asks the server to resolve the exact route, committed capacity, policies, fee, and payouts")
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro.weight(.heavy))
                .tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s2)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var subject: PricedRouteCommerceClient.Subject? {
        try? .init(type: subjectType, id: subjectId)
    }

    private func readCurrent() async {
        loading = true
        defer { loading = false }
        guard let subject else {
            errorMessage = "Open a persisted job or shipment before pricing its route."
            return
        }
        do {
            quote = try await client.currentQuote(subject: subject)
            errorMessage = nil
        } catch let error as EusoTripAPIError {
            // A missing current quote is a normal honest empty; authentication,
            // server, and decode failures remain visible.
            let isMissing: Bool
            switch error {
            case .trpcError(let message):
                isMissing = message.localizedCaseInsensitiveContains("not been created")
            case .httpStatus(404, let body):
                isMissing = body.localizedCaseInsensitiveContains("not been created")
            default:
                isMissing = false
            }
            if isMissing {
                quote = nil
                errorMessage = nil
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createPrice() async {
        guard let subject else {
            errorMessage = "Open a persisted job or shipment before pricing its route."
            return
        }
        pricing = true
        errorMessage = nil
        defer { pricing = false }
        do {
            quote = try await client.price(subject: subject)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func money(_ minor: String, currency: String, scale: Int) -> String {
        guard let exact = Decimal(string: minor, locale: Locale(identifier: "en_US_POSIX")) else {
            return "—"
        }
        var divisor = Decimal(1)
        if scale > 0 {
            for _ in 0..<scale { divisor *= 10 }
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = scale
        formatter.maximumFractionDigits = scale
        formatter.locale = .autoupdatingCurrent
        return formatter.string(from: NSDecimalNumber(decimal: exact / divisor))
            ?? "\(currency) \(exact / divisor)"
    }

    private func distance(_ meters: Int, mode: PricedRouteCommerceClient.Mode) -> String {
        switch mode {
        case .vessel:
            return String(format: "%.1f nmi", Double(meters) / 1_852.0)
        case .truck, .rail:
            return String(format: "%.1f mi", Double(meters) / 1_609.344)
        }
    }

    private func movementLabel(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private var modeIcon: String {
        switch subjectType {
        case .load: return "truck.box.fill"
        case .railShipment: return "tram.fill"
        case .vesselShipment, .vesselVoyage: return "ferry.fill"
        }
    }

    private func shortHash(_ value: String) -> String {
        String(value.prefix(10)).uppercased()
    }
}
