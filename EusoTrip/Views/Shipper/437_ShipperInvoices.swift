//
//  437_ShipperInvoices.swift
//  EusoTrip — Shipper · Invoice / AR Management (GLOVE FIT B-2).
//
//  Three surfaces, one file (the Contracts 217 pattern):
//    1. Invoice LIST   — status-filterable ledger, one row per invoice
//                        (number · customer · total · balance due · status
//                        chip · due date). Backed by `invoices.listInvoices`.
//    2. Invoice DETAIL — header card, line items, totals, balance-due,
//                        terms, dunning strip; CTAs send (`invoices.send-
//                        Invoice`) + record payment (`invoices.recordPayment`).
//                        Pushed in-stack via `\.rolePushDetail`.
//    3. CREATE flow    — load/settlement picker, line items, terms selector,
//                        notes, "send now" toggle. Backed by
//                        `invoices.createInvoice`. Pushed in-stack.
//
//  Doctrine:
//    • Zero fabrication — every field surfaces from the live ledger; a
//      blank money column renders an em-dash via `usd2`, never a $0.
//    • No-lingering-load — the shared EusoTripAPI session bounds every
//      call at 22s; every `loading` flag resolves in a `defer`.
//    • Push navigation only — detail + create slide in via the shared
//      `RoleDetailPush` layer (BespokeBackBar), no slide-up modals.
//    • Money terms (net15/30/…) are account-level AR concepts, not
//      mode-dependent freight terms, so they bypass TransportLexicon.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - 2-decimal money formatter (AR needs cents)
//
// The shared `usd()` in LifecycleScaffold drops the fraction (good for
// load rates); an AR ledger must show cents. nil/≤0-tolerant: a missing
// balance renders an em-dash, never a fabricated $0.00.

private func usd2(_ amount: Double?, allowZero: Bool = false) -> String {
    guard let v = amount, allowZero || v != 0 else { return "—" }
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
}

/// Human due-date with a relative overdue/today/in-N-days tail.
private func dueDisplay(_ iso: String?) -> String {
    guard let iso, !iso.isEmpty else { return "—" }
    return humanISO(iso, format: "MMM d, yyyy")
}

// MARK: - Status → pill kind + label

private func invoiceStatusKind(_ status: String) -> StatusPill.Kind {
    switch status.lowercased() {
    case "paid":    return .success
    case "partial": return .info
    case "sent":    return .info
    case "overdue": return .danger
    case "void":    return .neutral
    case "draft":   return .neutral
    default:        return .neutral
    }
}

private func termsLabel(_ terms: String?) -> String {
    switch (terms ?? "").lowercased() {
    case "due_on_receipt": return "Due on receipt"
    case "net15": return "Net 15"
    case "net30": return "Net 30"
    case "net45": return "Net 45"
    case "net60": return "Net 60"
    case "net90": return "Net 90"
    default: return dashIfEmpty(terms)
    }
}

// ============================================================================
// MARK: - 1) Invoice LIST
// ============================================================================

struct ShipperInvoicesScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ShipperInvoicesBody() } nav: { shipperLifecycleNav() }
    }
}

private struct ShipperInvoicesBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.rolePushDetail) private var pushDetail

    @State private var rows: [InvoicesAPI.InvoiceRow] = []
    @State private var statusFilter: String? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Last-good cache shown instantly on re-entry so a refresh never
    /// blanks the ledger (no-lingering-load doctrine).
    @State private var hasLoadedOnce = false

    private let filters: [(String?, String)] = [
        (nil, "All"),
        ("draft", "Draft"),
        ("sent", "Sent"),
        ("partial", "Partial"),
        ("overdue", "Overdue"),
        ("paid", "Paid"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if !rows.isEmpty { summaryStrip }
                filterStrip
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { if !hasLoadedOnce { await load() } }
        .eusoRefreshable { await load() }
    }

    // MARK: Header + create CTA

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.plaintext.fill")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · INVOICES & AR")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Invoices")
                    .font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Spacer()
                Button { openCreate() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("New invoice")
                    }
                    .font(.system(size: 12, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: AR summary strip (outstanding + overdue, computed from the page)
    //
    // Computed from the ROWS already on screen — never a separate
    // fabricated total. Honest "across N invoices" subtext.

    private var summaryStrip: some View {
        let outstanding = rows
            .filter { !["paid", "void"].contains($0.status.lowercased()) }
            .reduce(0.0) { $0 + ($1.balance ?? 0) }
        let overdue = rows
            .filter { $0.status.lowercased() == "overdue" }
            .reduce(0.0) { $0 + ($1.balance ?? 0) }
        return HStack(spacing: 10) {
            LifecycleStatTile(
                label: "OUTSTANDING",
                value: usd2(outstanding, allowZero: true),
                icon: "hourglass"
            )
            LifecycleStatTile(
                label: "OVERDUE",
                value: usd2(overdue, allowZero: true),
                icon: "exclamationmark.triangle.fill",
                danger: overdue > 0
            )
        }
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(filters, id: \.1) { f in
                    Button { Task { statusFilter = f.0; await load() } } label: {
                        Text(f.1)
                            .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(statusFilter == f.0 ? .white : palette.textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(statusFilter == f.0
                                        ? AnyShapeStyle(LinearGradient.diagonal)
                                        : AnyShapeStyle(palette.tintNeutral))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading && rows.isEmpty {
            ForEach(0..<3, id: \.self) { _ in invoiceSkeleton }
        } else if let err = loadError, rows.isEmpty {
            errorCard(err)
        } else if rows.isEmpty {
            EusoEmptyState(
                systemImage: "doc.text.magnifyingglass",
                title: "No invoices",
                subtitle: statusFilter.map { "Nothing matches the \($0) filter." }
                    ?? "Issue your first invoice from a delivered load or settlement.",
                cta: (label: "New invoice", action: { openCreate() })
            )
        } else {
            // Inline error banner over stale cache (refresh failed but we
            // keep the last-good ledger visible — no-lingering-load).
            if let err = loadError {
                LifecycleCard(accentWarning: true) {
                    LifecycleSection(label: "COULDN'T REFRESH", icon: "wifi.exclamationmark")
                    Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
            ForEach(rows) { row in
                Button { openDetail(row.id) } label: { invoiceRow(row) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func invoiceRow(_ r: InvoicesAPI.InvoiceRow) -> some View {
        LifecycleCard {
            HStack {
                Text(r.invoiceNumber)
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Spacer()
                StatusPill(text: r.status, kind: invoiceStatusKind(r.status))
            }
            LifecycleRow(label: "Customer", value: dashIfEmpty(r.customerName))
            LifecycleRow(label: "Total", value: usd2(r.total))
            LifecycleRow(label: "Balance due", value: usd2(r.balance, allowZero: r.status.lowercased() == "paid"))
            LifecycleRow(label: "Due", value: dueDisplay(r.dueAt))
        }
    }

    private var invoiceSkeleton: some View {
        LifecycleCard {
            HStack {
                RoundedRectangle(cornerRadius: 4).fill(palette.tintNeutral).frame(width: 120, height: 13)
                Spacer()
                RoundedRectangle(cornerRadius: 8).fill(palette.tintNeutral).frame(width: 54, height: 18)
            }
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4).fill(palette.tintNeutral).frame(height: 12)
            }
        }
        .redacted(reason: .placeholder)
    }

    private func errorCard(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            LifecycleSection(label: "COULDN'T LOAD", icon: "exclamationmark.triangle.fill")
            Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
            Button { Task { await load() } } label: {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    // MARK: Nav (push in-stack via the shared detail layer)

    private func openDetail(_ id: Int) {
        guard let pushDetail else { return }
        pushDetail("Invoice") {
            AnyView(ShipperInvoiceDetailBody(invoiceId: id, onChanged: {
                Task { await reloadInPlace() }
            }))
        }
    }

    private func openCreate() {
        guard let pushDetail else { return }
        pushDetail("New invoice") {
            AnyView(ShipperInvoiceCreateBody(onCreated: {
                Task { await reloadInPlace() }
            }))
        }
    }

    // MARK: Load

    private func load() async {
        loading = true
        loadError = nil
        defer { loading = false; hasLoadedOnce = true }
        do {
            let env = try await EusoTripAPI.shared.invoices.listInvoices(
                status: statusFilter, mineAsIssuer: true
            )
            rows = env.invoices
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Silent re-fetch (after a detail mutation) that keeps the current
    /// ledger on screen if it fails — no spinner flash.
    private func reloadInPlace() async {
        do {
            let env = try await EusoTripAPI.shared.invoices.listInvoices(
                status: statusFilter, mineAsIssuer: true
            )
            rows = env.invoices
            loadError = nil
        } catch {
            // Keep the last-good rows; surface the failure non-destructively.
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// ============================================================================
// MARK: - 2) Invoice DETAIL (pushed in-stack)
// ============================================================================

struct ShipperInvoiceDetailBody: View {
    @Environment(\.palette) private var palette
    let invoiceId: Int
    /// Called after any mutation (send / payment / void) so the parent
    /// list re-fetches.
    let onChanged: () -> Void

    @State private var detail: InvoicesAPI.InvoiceDetail? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Record-payment sheet state
    @State private var showPayment = false
    @State private var paymentAmount: String = ""
    @State private var paymentMethod: String = "ach"
    @State private var paymentReference: String = ""
    @State private var submitting = false
    @State private var actionError: String? = nil
    @State private var sending = false

    private let methods: [(String, String)] = [
        ("ach", "ACH"), ("wire", "Wire"), ("check", "Check"),
        ("card", "Card"), ("factoring", "Factoring"), ("cash", "Cash"), ("other", "Other"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let d = detail {
                    headerBlock(d.header)
                    if let banner = actionError {
                        LifecycleCard(accentDanger: true) {
                            LifecycleSection(label: "ACTION FAILED", icon: "exclamationmark.triangle.fill")
                            Text(banner).font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                    summaryCard(d.header)
                    lineItemsCard(d.lineItems)
                    totalsCard(d.header)
                    if !d.dunningEvents.isEmpty { dunningCard(d.dunningEvents) }
                    if let notes = d.header.notes, !notes.isEmpty { notesCard(notes) }
                    ctaRow(d.header)
                } else if loading {
                    skeleton
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        LifecycleSection(label: "COULDN'T LOAD", icon: "exclamationmark.triangle.fill")
                        Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
                        Button { Task { await load() } } label: {
                            Text("Retry").font(.system(size: 11, weight: .heavy)).tracking(0.6)
                                .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8)
                                .background(LinearGradient.diagonal).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                } else {
                    EusoEmptyState(
                        systemImage: "doc.text",
                        title: "Invoice not found",
                        subtitle: "This invoice is no longer in the ledger."
                    )
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, Space.s4)
        }
        .eusoRefreshTask { await load() }
        .sheet(isPresented: $showPayment) { paymentSheet }
    }

    // MARK: Header

    private func headerBlock(_ h: InvoicesAPI.InvoiceRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(h.invoiceNumber)
                    .font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Spacer()
                StatusPill(text: h.status, kind: invoiceStatusKind(h.status))
            }
            Text(dashIfEmpty(h.customerName))
                .font(EType.body).foregroundStyle(palette.textSecondary)
        }
    }

    private func summaryCard(_ h: InvoicesAPI.InvoiceRow) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "BALANCE DUE", icon: "creditcard")
            Text(usd2(h.balance, allowZero: h.status.lowercased() == "paid"))
                .font(.system(size: 28, weight: .heavy)).foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            HStack(spacing: 10) {
                LifecycleStatTile(label: "TERMS", value: termsLabel(h.terms), icon: "calendar")
                LifecycleStatTile(
                    label: "DUE",
                    value: dueDisplay(h.dueAt),
                    icon: "clock",
                    danger: h.status.lowercased() == "overdue"
                )
            }
        }
    }

    private func lineItemsCard(_ items: [InvoicesAPI.InvoiceLine]) -> some View {
        LifecycleCard {
            LifecycleSection(label: "LINE ITEMS", icon: "list.bullet.rectangle")
            if items.isEmpty {
                Text("No line items on file.").font(EType.caption).foregroundStyle(palette.textTertiary)
            } else {
                ForEach(items) { li in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(dashIfEmpty(li.description))
                                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Spacer(minLength: Space.s2)
                            Text(usd2(li.amount, allowZero: true))
                                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary).monospacedDigit()
                        }
                        Text(lineDetail(li))
                            .font(EType.caption).foregroundStyle(palette.textTertiary)
                    }
                    if li.id != items.last?.id {
                        Divider().overlay(palette.borderFaint)
                    }
                }
            }
        }
    }

    private func lineDetail(_ li: InvoicesAPI.InvoiceLine) -> String {
        let qty = li.qty.map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.3f", $0) } ?? "—"
        let rate = usd2(li.rate, allowZero: true)
        let taxFlag = li.taxable ? " · taxable" : ""
        return "\(qty) × \(rate)\(taxFlag)"
    }

    private func totalsCard(_ h: InvoicesAPI.InvoiceRow) -> some View {
        LifecycleCard {
            LifecycleSection(label: "TOTALS", icon: "sum")
            LifecycleRow(label: "Subtotal", value: usd2(h.subtotal, allowZero: true))
            LifecycleRow(label: "Tax", value: usd2(h.tax, allowZero: true))
            LifecycleRow(label: "Total", value: usd2(h.total, allowZero: true))
            LifecycleRow(label: "Paid", value: usd2(h.amountPaid, allowZero: true))
            Divider().overlay(palette.borderFaint)
            HStack {
                Text("Balance due").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Spacer()
                Text(usd2(h.balance, allowZero: h.status.lowercased() == "paid"))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(h.status.lowercased() == "overdue" ? Brand.danger : palette.textPrimary)
                    .monospacedDigit()
            }
        }
    }

    private func dunningCard(_ events: [InvoicesAPI.DunningEvent]) -> some View {
        LifecycleCard(accentWarning: true) {
            LifecycleSection(label: "DUNNING HISTORY", icon: "bell.badge")
            ForEach(events) { e in
                HStack {
                    Text("Level \(e.level ?? 1) · \(channelLabel(e.channel))")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(humanISO(e.sentAt, format: "MMM d"))
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                }
                if let d = e.daysOverdue, d > 0 {
                    Text("\(d) days past due when sent")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private func channelLabel(_ c: String?) -> String {
        switch (c ?? "").lowercased() {
        case "email": return "Email"
        case "sms": return "SMS"
        case "push": return "Push"
        case "in_app": return "In-app"
        default: return dashIfEmpty(c)
        }
    }

    private func notesCard(_ notes: String) -> some View {
        LifecycleCard {
            LifecycleSection(label: "NOTES", icon: "note.text")
            Text(notes).font(EType.body).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: CTAs

    @ViewBuilder
    private func ctaRow(_ h: InvoicesAPI.InvoiceRow) -> some View {
        let status = h.status.lowercased()
        let canSend = status == "draft"
        let canPay = !["paid", "void"].contains(status)
        VStack(spacing: 10) {
            if canSend {
                Button { Task { await send(h.id) } } label: {
                    sendLabel
                }.buttonStyle(.plain).disabled(sending)
            }
            if canPay {
                Button {
                    paymentAmount = ""
                    paymentReference = ""
                    actionError = nil
                    showPayment = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "dollarsign.circle.fill")
                        Text("Record payment")
                    }
                    .font(.system(size: 14, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .overlay(Capsule().strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
                }.buttonStyle(.plain)
            }
            if status == "void" {
                Text("This invoice is void.").font(EType.caption).foregroundStyle(palette.textTertiary)
            }
            if status == "paid" {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.success)
                    Text("Paid in full").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private var sendLabel: some View {
        HStack(spacing: 6) {
            if sending { ProgressView().tint(.white) }
            else { Image(systemName: "paperplane.fill") }
            Text(sending ? "Sending…" : "Send invoice")
        }
        .font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(LinearGradient.diagonal).clipShape(Capsule())
        .opacity(sending ? 0.7 : 1)
    }

    // MARK: Record-payment sheet

    private var paymentSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if let h = detail?.header {
                        LifecycleCard {
                            LifecycleRow(label: "Invoice", value: h.invoiceNumber)
                            LifecycleRow(label: "Balance due", value: usd2(h.balance, allowZero: true))
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AMOUNT").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        TextField("0.00", text: $paymentAmount)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(palette.bgCardSoft)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        if let h = detail?.header, let bal = h.balance {
                            Button { paymentAmount = String(format: "%.2f", bal) } label: {
                                Text("Pay full balance · \(usd2(bal, allowZero: true))")
                                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                            }.buttonStyle(.plain)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("METHOD").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(methods, id: \.0) { m in
                                    Button { paymentMethod = m.0 } label: {
                                        Text(m.1)
                                            .font(.system(size: 11, weight: .heavy))
                                            .foregroundStyle(paymentMethod == m.0 ? .white : palette.textPrimary)
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(paymentMethod == m.0
                                                        ? AnyShapeStyle(LinearGradient.diagonal)
                                                        : AnyShapeStyle(palette.tintNeutral))
                                            .clipShape(Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("REFERENCE (OPTIONAL)").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        TextField("Check #, wire ref, confirmation…", text: $paymentReference)
                            .font(EType.body).foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(palette.bgCardSoft)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    if let err = actionError {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    Button { Task { await recordPayment() } } label: {
                        HStack(spacing: 6) {
                            if submitting { ProgressView().tint(.white) }
                            Text(submitting ? "Recording…" : "Record payment")
                        }
                        .font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                        .opacity((submitting || !amountIsValid) ? 0.6 : 1)
                    }.buttonStyle(.plain).disabled(submitting || !amountIsValid)
                }
                .padding(16)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("Record payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPayment = false }
                }
            }
        }
        .environment(\.palette, palette)
    }

    private var amountIsValid: Bool {
        guard let v = Double(paymentAmount.trimmingCharacters(in: .whitespaces)), v > 0 else { return false }
        return true
    }

    // MARK: Actions

    private func load() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            detail = try await EusoTripAPI.shared.invoices.getInvoice(id: invoiceId)
            if detail == nil { loadError = nil }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func send(_ id: Int) async {
        sending = true
        actionError = nil
        defer { sending = false }
        do {
            let res = try await EusoTripAPI.shared.invoices.sendInvoice(id: id)
            if res.storageDegraded {
                actionError = "Sent — but the PDF couldn't be stored (storage offline). Status advanced to \(res.status)."
            }
            await load()
            onChanged()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func recordPayment() async {
        guard let v = Double(paymentAmount.trimmingCharacters(in: .whitespaces)), v > 0 else { return }
        submitting = true
        actionError = nil
        defer { submitting = false }
        do {
            _ = try await EusoTripAPI.shared.invoices.recordPayment(
                id: invoiceId,
                amount: v,
                method: paymentMethod,
                reference: paymentReference.isEmpty ? nil : paymentReference
            )
            showPayment = false
            await load()
            onChanged()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ForEach(0..<3, id: \.self) { _ in
                LifecycleCard {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4).fill(palette.tintNeutral).frame(height: 12)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
    }
}

// ============================================================================
// MARK: - 3) CREATE flow (pushed in-stack)
// ============================================================================

struct ShipperInvoiceCreateBody: View {
    @Environment(\.palette) private var palette
    /// Called after a successful create so the list re-fetches. The
    /// pushed layer is dismissed by the shared back bar.
    let onCreated: () -> Void

    // Source picker
    @State private var loads: [ShipperAPI.MyLoad] = []
    @State private var loadsLoading = true
    @State private var loadsError: String? = nil
    @State private var selectedLoad: ShipperAPI.MyLoad? = nil

    // Line items + terms + notes
    @State private var lineItems: [InvoicesAPI.NewLineItem] = []
    @State private var terms: String = "net30"
    @State private var taxRatePct: String = ""
    @State private var notes: String = ""
    @State private var sendNow: Bool = false

    // New-line entry
    @State private var newDesc: String = ""
    @State private var newQty: String = "1"
    @State private var newRate: String = ""
    @State private var newTaxable: Bool = false

    // Submit
    @State private var submitting = false
    @State private var submitError: String? = nil
    @State private var created: InvoicesAPI.CreateResult? = nil

    private let termOptions: [(String, String)] = [
        ("due_on_receipt", "On receipt"),
        ("net15", "Net 15"), ("net30", "Net 30"), ("net45", "Net 45"),
        ("net60", "Net 60"), ("net90", "Net 90"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let c = created {
                    successCard(c)
                } else {
                    sourceCard
                    lineItemsCard
                    addLineCard
                    termsCard
                    notesCard
                    if let err = submitError {
                        LifecycleCard(accentDanger: true) {
                            LifecycleSection(label: "COULDN'T CREATE", icon: "exclamationmark.triangle.fill")
                            Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                    submitButton
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, Space.s4)
        }
        .eusoRefreshTask { await loadSources() }
    }

    // MARK: Source picker (load → derives customer + line haul server-side)

    private var sourceCard: some View {
        LifecycleCard {
            LifecycleSection(label: "BILL FOR (OPTIONAL)", icon: "shippingbox")
            Text("Pick a delivered load to auto-fill the customer and freight charge, or skip and add line items manually.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
            if loadsLoading {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8).fill(palette.tintNeutral).frame(height: 40)
                        .redacted(reason: .placeholder)
                }
            } else if let err = loadsError {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            } else if loads.isEmpty {
                Text("No loads available to bill. Add line items below instead.")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
            } else {
                ForEach(loads.prefix(20)) { l in
                    Button { selectLoad(l) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.loadNumber)
                                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                                Text("\(l.origin) → \(l.destination)")
                                    .font(EType.caption).foregroundStyle(palette.textTertiary)
                            }
                            Spacer()
                            if selectedLoad?.id == l.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(LinearGradient.diagonal)
                            } else {
                                Image(systemName: "circle").foregroundStyle(palette.textTertiary)
                            }
                        }
                        .padding(.vertical, 8)
                    }.buttonStyle(.plain)
                    if l.id != loads.prefix(20).last?.id { Divider().overlay(palette.borderFaint) }
                }
            }
        }
    }

    private var lineItemsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LINE ITEMS", icon: "list.bullet.rectangle")
            if lineItems.isEmpty {
                Text(selectedLoad == nil
                     ? "Add at least one line item, or pick a load above (the server derives the freight charge)."
                     : "Freight charge will be derived from the selected load. Add extra line items below if needed.")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
            } else {
                ForEach(lineItems) { li in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(li.description.isEmpty ? "—" : li.description)
                                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text("\(formatQty(li.qty)) × \(usd2(li.rate, allowZero: true))\(li.taxable ? " · taxable" : "")")
                                .font(EType.caption).foregroundStyle(palette.textTertiary)
                        }
                        Spacer()
                        Text(usd2(li.qty * li.rate, allowZero: true))
                            .font(EType.bodyStrong).foregroundStyle(palette.textPrimary).monospacedDigit()
                        Button { lineItems.removeAll { $0.id == li.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(Brand.danger)
                        }.buttonStyle(.plain)
                    }
                    if li.id != lineItems.last?.id { Divider().overlay(palette.borderFaint) }
                }
                Divider().overlay(palette.borderFaint)
                HStack {
                    Text("Subtotal").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(usd2(subtotal, allowZero: true))
                        .font(.system(size: 16, weight: .heavy)).foregroundStyle(palette.textPrimary).monospacedDigit()
                }
            }
        }
    }

    private var addLineCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ADD LINE ITEM", icon: "plus")
            TextField("Description (e.g. Detention, Lumper fee)", text: $newDesc)
                .font(EType.body).foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(palette.bgCardSoft).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("QTY").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    TextField("1", text: $newQty)
                        .keyboardType(.decimalPad)
                        .font(EType.body).foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(palette.bgCardSoft).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("RATE").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    TextField("0.00", text: $newRate)
                        .keyboardType(.decimalPad)
                        .font(EType.body).foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(palette.bgCardSoft).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
            }
            Toggle(isOn: $newTaxable) {
                Text("Taxable").font(EType.body).foregroundStyle(palette.textPrimary)
            }.tint(Brand.blue)
            Button { addLine() } label: {
                Text("Add line")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .overlay(Capsule().strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
            }.buttonStyle(.plain).disabled(!newLineValid).opacity(newLineValid ? 1 : 0.5)
        }
    }

    private var termsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "TERMS", icon: "calendar")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(termOptions, id: \.0) { t in
                        Button { terms = t.0 } label: {
                            Text(t.1)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(terms == t.0 ? .white : palette.textPrimary)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(terms == t.0
                                            ? AnyShapeStyle(LinearGradient.diagonal)
                                            : AnyShapeStyle(palette.tintNeutral))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Text("Tax rate %").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
                TextField("0", text: $taxRatePct)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .frame(width: 70)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCardSoft).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
        }
    }

    private var notesCard: some View {
        LifecycleCard {
            LifecycleSection(label: "NOTES (OPTIONAL)", icon: "note.text")
            TextField("Memo for the customer…", text: $notes, axis: .vertical)
                .lineLimit(2...5)
                .font(EType.body).foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(palette.bgCardSoft).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            Toggle(isOn: $sendNow) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Send immediately").font(EType.body).foregroundStyle(palette.textPrimary)
                    Text("Generates the PDF and advances draft → sent.")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                }
            }.tint(Brand.blue)
        }
    }

    private var submitButton: some View {
        Button { Task { await submit() } } label: {
            HStack(spacing: 6) {
                if submitting { ProgressView().tint(.white) }
                Image(systemName: sendNow ? "paperplane.fill" : "doc.badge.plus")
                Text(submitting ? "Creating…" : (sendNow ? "Create & send" : "Create draft"))
            }
            .font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(LinearGradient.diagonal).clipShape(Capsule())
            .opacity((submitting || !canSubmit) ? 0.6 : 1)
        }.buttonStyle(.plain).disabled(submitting || !canSubmit)
    }

    private func successCard(_ c: InvoicesAPI.CreateResult) -> some View {
        VStack(spacing: Space.s4) {
            LifecycleCard(accentGradient: true) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.success)
                    Text("Invoice created").font(EType.title).foregroundStyle(palette.textPrimary)
                }
                LifecycleRow(label: "Number", value: c.invoiceNumber)
                LifecycleRow(label: "Status", value: c.status.uppercased())
                LifecycleRow(label: "Total", value: usd2(c.total, allowZero: true))
                if c.sent == true {
                    if c.storageDegraded == true {
                        Text("Sent — PDF storage is offline, so the document couldn't be stored. Status still advanced.")
                            .font(EType.caption).foregroundStyle(Brand.warning)
                    } else {
                        Text("Sent — PDF generated.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
            }
            Text("Tap back to return to the ledger.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Derived

    private var subtotal: Double { lineItems.reduce(0) { $0 + $1.qty * $1.rate } }

    private var newLineValid: Bool {
        guard !newDesc.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let q = Double(newQty), q > 0 else { return false }
        guard Double(newRate) != nil else { return false }
        return true
    }

    /// Server requires a load/settlement OR explicit line items. We mirror
    /// that here so the button only enables when the server would accept.
    private var canSubmit: Bool {
        selectedLoad != nil || !lineItems.isEmpty
    }

    private func formatQty(_ q: Double) -> String {
        q == q.rounded() ? String(Int(q)) : String(format: "%.3f", q)
    }

    // MARK: Actions

    private func selectLoad(_ l: ShipperAPI.MyLoad) {
        selectedLoad = (selectedLoad?.id == l.id) ? nil : l
    }

    private func addLine() {
        guard newLineValid, let q = Double(newQty), let r = Double(newRate) else { return }
        lineItems.append(.init(
            description: newDesc.trimmingCharacters(in: .whitespaces),
            qty: q, rate: r, taxable: newTaxable
        ))
        newDesc = ""; newQty = "1"; newRate = ""; newTaxable = false
    }

    private func loadSources() async {
        loadsLoading = true
        loadsError = nil
        defer { loadsLoading = false }
        do {
            // Delivered loads are the canonical billable source; fall back
            // to all loads if the status filter returns nothing.
            var fetched = try await EusoTripAPI.shared.shipper.getMyLoads(status: "delivered", limit: 30)
            if fetched.isEmpty {
                fetched = try await EusoTripAPI.shared.shipper.getMyLoads(limit: 30)
            }
            loads = fetched
        } catch {
            loadsError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        submitting = true
        submitError = nil
        defer { submitting = false }
        // `shippers.getMyLoads` returns id as "load_<n>" — strip the
        // prefix to the bare numeric load id the invoices router expects.
        // Matches the convention in 228_ShipperBOLs.
        let loadIdInt = selectedLoad.flatMap {
            Int($0.id.replacingOccurrences(of: "load_", with: ""))
        }
        let taxRate = (Double(taxRatePct) ?? 0) / 100.0
        do {
            let res = try await EusoTripAPI.shared.invoices.createInvoice(
                loadId: loadIdInt,
                terms: terms,
                taxRate: max(0, min(1, taxRate)),
                lineItems: lineItems.isEmpty ? nil : lineItems,
                notes: notes.isEmpty ? nil : notes,
                autoSend: sendNow
            )
            created = res
            onCreated()
        } catch {
            submitError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Previews

#Preview("437 · Invoices · Night") {
    ShipperInvoicesScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("437 · Invoices · Day") {
    ShipperInvoicesScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
