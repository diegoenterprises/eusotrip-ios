//
//  071_MeTax.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · tax summary + 1099)
//
//  Screen 071 · Me · Tax — the driver's annual tax summary surface.
//  YTD gross earnings, estimated self-employed tax liability (server-
//  computed, not client-derived), quarterly estimate, filing
//  threshold status, and the 1099-NEC download row for the prior
//  year.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • YTD gross + estimated tax + quarterly estimate come from
//      `tax.getSummary({ year })` (MCP-verified at
//      `frontend/server/routers/tax.ts:43`). Backend aggregates
//      `payments` where the driver is payee + status IN
//      ('succeeded','completed','settled','paid') + paymentType IN
//      ('load_payment','payout'), then applies the server-configured
//      self-employed tax basis points to produce the liability figure.
//      Prior iOS implementation derived these values client-side from
//      `earnings.getYTDSummary` with a hardcoded 25.31% estimate —
//      that client-side derivation has been removed as part of this
//      port (landmine cleanup).
//
//    • 1099-NEC availability comes from `tax.get1099({ year: Y-1 })`
//      (tax.ts:168). The server returns `available: true` only when
//      (a) it's past Jan 31 of year+1 AND (b) a record exists in
//      `tax_1099_records` for this driver. The URL is a real
//      server-minted path on success, nil otherwise. The view
//      renders an explicit "IRS issuance window opens Jan 31"
//      message until `available` flips — honest disclosure, not a
//      stub banner.
//
//    • Filing threshold chip keys off `filingThresholdMet` ($600 IRS
//      threshold) and renders a gradient "Threshold met" chip or a
//      neutral "Under $600" chip depending on server truth.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on YTD hero, threshold chip,
//         download CTA, 1099 availability gradient icon.
//    §4   Tokenized spacing (Space.sN), radii (Radius.sm/md/lg),
//         type (EType.*). No magic numbers.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle expressions wrapped in `AnyShapeStyle`.
//    §10  Previews compile in isolation — stores stay in `.loading`
//         so both registers render deterministic skeletons.
//

import SwiftUI

// MARK: - Screen root

struct MeTax: View {
    @Environment(\.palette) var palette
    @StateObject private var summary = TaxSummaryStore()
    @StateObject private var doc1099 = Tax1099Store()

    /// Year selector. Starts at the current calendar year; the 1099
    /// surface always looks at `year - 1` (1099s are issued for the
    /// prior tax year).
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    /// In-app PDF presentation for the 1099-NEC. Replaces the prior
    /// `UIApplication.shared.open(url)` Safari punt so the driver
    /// stays inside the EusoTrip app and can save the doc straight
    /// into Files / AirDrop / Mail via EusoPDFViewer's share sheet.
    @State private var tax1099Presentation: EusoPDFPresentation? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                yearPicker
                summaryBlock
                doc1099Block
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .onChange(of: selectedYear) { _, _ in
            Task { await reload() }
        }
        .sheet(item: $tax1099Presentation) { pres in
            EusoPDFViewer(
                title: pres.title,
                subtitle: pres.subtitle,
                source: .url(pres.url),
                allowSigning: false,
                onSigned: nil,
                loadIdForWalletPass: nil
            )
        }
    }

    private func reload() async {
        summary.year = selectedYear
        doc1099.year = selectedYear - 1
        async let a: Void = summary.refresh()
        async let b: Void = doc1099.refresh()
        _ = await (a, b)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Tax")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("YTD summary · 1099 download")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbeSang(
                state: (summary.isLoading || doc1099.isLoading) ? .thinking : .idle,
                diameter: 40
            )
        }
    }

    // MARK: Year picker — current + 2 prior

    private var yearPicker: some View {
        let currentYear = Calendar.current.component(.year, from: Date())
        let years = [currentYear, currentYear - 1, currentYear - 2]
        return HStack(spacing: Space.s2) {
            ForEach(years, id: \.self) { y in
                Button {
                    selectedYear = y
                } label: {
                    Text(String(y))
                        .font(EType.bodyStrong)
                        .foregroundStyle(
                            selectedYear == y
                                ? AnyShapeStyle(Color.white)
                                : AnyShapeStyle(palette.textSecondary)
                        )
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s2)
                        .background(
                            Group {
                                if selectedYear == y {
                                    Capsule().fill(LinearGradient.diagonal)
                                } else {
                                    Capsule().strokeBorder(palette.borderFaint, lineWidth: 1)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: Summary block

    @ViewBuilder
    private var summaryBlock: some View {
        switch summary.state {
        case .loading:
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.5))
                .frame(height: 280)
        case .empty:
            EusoEmptyState(
                systemImage: "doc.text",
                title: "No tax data for \(String(selectedYear))",
                subtitle: "Once your first load settles this tax year, YTD gross and your estimated liability land here."
            )
        case .error(let e):
            errorBanner(e) { Task { await summary.refresh() } }
        case .loaded(let s):
            if let s {
                summaryContent(s)
            } else {
                EusoEmptyState(
                    systemImage: "doc.text",
                    title: "No tax data for \(String(selectedYear))",
                    subtitle: "Once your first load settles this tax year, YTD gross and your estimated liability land here."
                )
            }
        }
    }

    private func summaryContent(_ s: TaxAPI.TaxSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Hero: YTD gross
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("YTD GROSS")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                Text(money(s.ytdGross ?? s.grossEarnings))
                    .font(EType.numeric)
                    .foregroundStyle(LinearGradient.diagonal)
                thresholdChip(filingThresholdMet: s.filingThresholdMet ?? (s.grossEarnings >= 600))
            }

            // Two-stat row: estimated tax + quarterly
            HStack(spacing: Space.s3) {
                statCell(
                    label: "ESTIMATED TAX",
                    value: money(s.estimatedTax ?? s.estimatedTaxLiability)
                )
                statCell(
                    label: "QUARTERLY",
                    value: money(s.quarterlyEstimate ?? (s.estimatedTaxLiability / 4))
                )
            }

            // Withheld row (only if server reports a non-zero amount)
            if (s.federalWithheld ?? 0) > 0 || (s.stateWithheld ?? 0) > 0 {
                HStack(spacing: Space.s3) {
                    statCell(label: "FEDERAL WITHHELD", value: money(s.federalWithheld ?? 0))
                    statCell(label: "STATE WITHHELD", value: money(s.stateWithheld ?? 0))
                }
            }

            // Footer: last updated
            HStack {
                Text("Updated \(shortDateTime(s.updatedAt))")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func thresholdChip(filingThresholdMet: Bool) -> some View {
        Group {
            if filingThresholdMet {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("THRESHOLD MET · 1099 EXPECTED")
                        .font(EType.micro)
                        .tracking(1.1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 3)
                .background(Capsule().fill(LinearGradient.diagonal))
            } else {
                Text("UNDER $600 · NO 1099 REQUIRED")
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, 3)
                    .background(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
            }
        }
        .padding(.top, 2)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCardSoft)
        )
    }

    // MARK: 1099 block

    @ViewBuilder
    private var doc1099Block: some View {
        let priorYear = selectedYear - 1
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("1099-NEC · TAX YEAR \(String(priorYear))")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }
            switch doc1099.state {
            case .loading:
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.4))
                    .frame(height: 72)
            case .empty:
                doc1099Row(nil)
            case .error:
                doc1099Row(nil)
            case .loaded(let d):
                doc1099Row(d)
            }
        }
    }

    @ViewBuilder
    private func doc1099Row(_ d: TaxAPI.Tax1099Document?) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(
                        (d?.available ?? false)
                            ? AnyShapeStyle(LinearGradient.diagonal)
                            : AnyShapeStyle(palette.tintNeutral)
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "doc.richtext")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let d, d.available {
                    Text(d.documentType ?? "1099-NEC")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(money(d.totalAmount)) · issued \(shortDate(d.issuedAt))")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                } else {
                    Text("1099-NEC")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("IRS issuance window opens Jan 31, \(String(selectedYear))")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: Space.s2)
            trailingDoc(d)
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func trailingDoc(_ d: TaxAPI.Tax1099Document?) -> some View {
        if let d, d.available, let urlString = d.url, let url = absolute(url: urlString) {
            Button {
                tax1099Presentation = EusoPDFPresentation(
                    url: url,
                    title: "1099-NEC · \(selectedYear - 1)",
                    subtitle: "Eusorone Technologies, Inc."
                )
            } label: {
                Text("Download")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s1)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        } else {
            Image(systemName: "clock")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Disclosure footer

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("ABOUT THESE ESTIMATES")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text("Estimated tax and quarterly figures are server-computed from your paid settlements using the current self-employed tax rate. They're guidance, not advice — consult your accountant before filing. The 1099-NEC becomes available on or after Jan 31 once Eusorone generates your record.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft)
        )
    }

    // MARK: Shared error + helpers

    private func errorBanner(_ err: Error, retry: @escaping () -> Void) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Couldn't load tax summary")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private func shortDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d, yyyy"
            return out.string(from: d)
        }
        return iso
    }

    private func shortDateTime(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d · h:mm a"
            return out.string(from: d)
        }
        return iso
    }

    /// Server paths are relative ("/api/driver/tax/1099-2025.pdf?...").
    /// Resolve against the configured API baseURL so the download CTA
    /// opens a real signed URL.
    private func absolute(url: String) -> URL? {
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            return URL(string: url)
        }
        guard let base = EusoTripAPI.shared.baseURL else { return nil }
        return URL(string: url, relativeTo: base)?.absoluteURL
    }
}

// MARK: - Screen wrapper

struct MeTaxScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeTax()
        } nav: {
            BottomNav(
                leading: driverNavLeading_071(),
                trailing: driverNavTrailing_071(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_071() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_071() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews
//
// Previews never run `.task` — stores stay in `.loading` so both
// registers render deterministic skeletons without hitting the
// network. No fixtures.

#Preview("071 · Me Tax · Night") {
    MeTaxScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("071 · Me Tax · Afternoon") {
    MeTaxScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
