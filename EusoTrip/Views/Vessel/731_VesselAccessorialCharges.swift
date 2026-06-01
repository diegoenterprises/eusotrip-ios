//
//  731_VesselAccessorialCharges.swift
//  EusoTrip — Vessel Operator · Accessorial Charges (PURPOSE-BUILT LEDGER).
//
//  Verbatim bespoke port of canonical wireframe "731 Vessel Accessorial
//  Charges · Light/Dark" (06 Vessel · Vessel Operator). LEDGER archetype:
//  category-keyed accessorial line items + a subtotal footer (distinct from
//  the container-LFD rows of the demurrage surfaces). Every chassis /
//  congestion / reefer / exam / demurrage fee on a booking is itemized by
//  code so the billable lines invoice cleanly while a disputed line is held
//  back automatically.
//
//  Docked under SHIPMENTS. transportMode=vessel · US (USOAK · USD).
//
//  REAL WIRING (tRPC · server/routers/detentionAccessorials.ts):
//    · detentionAccessorials.getAccessorialBilling  {status:"approved", batchSize}
//        -> pendingCharges (the APPLIED / billable lines) + batchSummary
//        (totalItems, totalAmount, byType, readyToInvoice)   (:1466)
//    · detentionAccessorials.getAccessorialDisputes {limit}
//        -> disputes (the DISPUTED lines, held back) + summary
//        (total, totalDisputedAmount)                         (:1217)
//    · detentionAccessorials.getAccessorialCatalog  {}
//        -> items[{code,name,category,defaultRate,unit,freeTime,description}]
//        backing the "Add line" picker                        (:772)
//    · detentionAccessorials.applyAccessorial  mutation
//        {loadId, chargeCode, amount, description, quantity}
//        -> writes an accessorial charge row to detention_claims, backing
//        the "Apply to invoice" CTA (blockchain audit + WS billing).  (:824)
//
//  RBAC: reads/writes protectedProcedure. NO mock data — every line, count,
//  and dollar derives from a live endpoint, with real loading / error /
//  honest-empty states. The "Apply to invoice" CTA needs a bound load to
//  write against; when unbound it surfaces the real gap honestly rather than
//  faking a success toast.
//

import SwiftUI

struct VesselAccessorialChargesScreen: View {
    let theme: Theme.Palette
    /// Booking/load the accessorial ledger belongs to. Defaults to 0 so the
    /// screen stays constructable from the ScreenRegistry (mirrors 700). When
    /// opened from a specific booking the caller injects the real load id; the
    /// "Apply to invoice" write targets it.
    var loadId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselAccessorialChargesBody(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

/// detentionAccessorials.getAccessorialBilling -> { pendingCharges, batchSummary }
private struct AccessorialBilling731: Decodable {
    let pendingCharges: [AccessorialBillingRow731]
    let batchSummary: AccessorialBatchSummary731?
}

private struct AccessorialBatchSummary731: Decodable {
    let totalItems: Int?
    let totalAmount: Double?
    let readyToInvoice: Int?
}

/// One billable (APPLIED) accessorial line. `type` carries the server's charge
/// code/type string (e.g. "CHC", "demurrage", "detention").
private struct AccessorialBillingRow731: Decodable, Identifiable {
    let id: Int
    let loadId: Int?
    let type: String?
    let amount: Double?
    let status: String?
    let facilityName: String?
    let shipperName: String?
    let carrierName: String?
    let origin: String?
    let destination: String?
}

/// detentionAccessorials.getAccessorialDisputes -> { disputes, summary }
private struct AccessorialDisputes731: Decodable {
    let disputes: [AccessorialDisputeRow731]
    let summary: AccessorialDisputeSummary731?
}

private struct AccessorialDisputeSummary731: Decodable {
    let total: Int?
    let totalDisputedAmount: Double?
}

/// One disputed (held-back) accessorial line.
private struct AccessorialDisputeRow731: Decodable, Identifiable {
    let id: Int
    let claimId: Int?
    let loadId: Int?
    let type: String?
    let originalAmount: Double?
    let disputedAmount: Double?
    let reason: String?
    let status: String?
    let carrierName: String?
    let shipperName: String?
}

/// detentionAccessorials.getAccessorialCatalog -> { items, categories, total }
private struct AccessorialCatalog731: Decodable {
    let items: [AccessorialCatalogItem731]
    let total: Int?
}

private struct AccessorialCatalogItem731: Decodable, Identifiable {
    var id: String { code }
    let code: String
    let name: String
    let category: String?
    let defaultRate: Double?
    let unit: String?
    let freeTime: Int?
    let description: String?
}

/// detentionAccessorials.applyAccessorial mutation result.
private struct ApplyAccessorialResult731: Decodable {
    let success: Bool?
    let loadId: Int?
    let chargeCode: String?
    let amount: Double?
    let status: String?
}

/// A normalized ledger line rendered in the CHARGE LINES card. Folds a
/// billable row or a disputed row into one shape so the list reads as one
/// code-keyed ledger (mirroring the five SVG rows).
private struct AccessorialLine731: Identifiable {
    enum State { case applied, disputed }
    let id: String
    let code: String           // "CHC", "DEM", …
    let title: String          // "Chassis split", "Demurrage overage", …
    let meta: String           // "CHC · USOAK · 3 days"
    let amount: Double
    let state: State
}

// MARK: - Body

private struct VesselAccessorialChargesBody: View {
    let loadId: Int

    @Environment(\.palette) private var palette

    @State private var billing: AccessorialBilling731? = nil
    @State private var disputes: AccessorialDisputes731? = nil
    @State private var catalog: AccessorialCatalog731? = nil

    @State private var loading = true
    @State private var loadError: String? = nil

    // Apply-to-invoice CTA state.
    @State private var applying = false
    @State private var applyAck: String? = nil
    @State private var applyError: String? = nil

    // Add-line picker state (driven by the live catalog).
    @State private var showCatalog = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)

                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(Brand.danger)
                                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            }
                        }
                    } else {
                        heroCard
                        chargeLinesSection
                        if let ack = applyAck { ackBanner(ack) }
                        if let err = applyError { errorBanner(err) }
                        ctaRow
                        if showCatalog { catalogSection }
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Derived ledger

    /// The APPLIED (billable) lines from getAccessorialBilling.
    private var appliedLines: [AccessorialLine731] {
        (billing?.pendingCharges ?? []).map { row in
            AccessorialLine731(
                id: "bill-\(row.id)",
                code: chargeCode(for: row.type),
                title: chargeTitle(for: row.type),
                meta: appliedMeta(row),
                amount: row.amount ?? 0,
                state: .applied)
        }
    }

    /// The DISPUTED (held-back) lines from getAccessorialDisputes.
    private var disputedLines: [AccessorialLine731] {
        (disputes?.disputes ?? []).map { row in
            AccessorialLine731(
                id: "disp-\(row.id)",
                code: chargeCode(for: row.type),
                title: chargeTitle(for: row.type),
                meta: disputedMeta(row),
                amount: row.disputedAmount ?? row.originalAmount ?? 0,
                state: .disputed)
        }
    }

    /// Full ledger — billable first, disputed held to the bottom (matching the
    /// SVG where the disputed DEM row sits last before the subtotal).
    private var lines: [AccessorialLine731] { appliedLines + disputedLines }

    private var billableCount: Int { appliedLines.count }
    private var disputedCount: Int { disputedLines.count }
    private var lineCount: Int { lines.count }

    /// Grand total (all lines, billable + disputed) — the hero figure.
    private var grandTotal: Double {
        lines.reduce(0) { $0 + $1.amount }
    }

    /// Subtotal of only the billable lines — the footer figure ("4 billable").
    private var billableSubtotal: Double {
        if let t = billing?.batchSummary?.totalAmount, t > 0 { return t }
        return appliedLines.reduce(0) { $0 + $1.amount }
    }

    /// Booking reference for the eyebrow / hero corner ("VES-260518").
    private var bookingRef: String {
        if loadId > 0 { return "VES-\(loadId)" }
        if let l = billing?.pendingCharges.first?.loadId, l > 0 { return "VES-\(l)" }
        if let l = disputes?.disputes.first?.loadId, l > 0 { return "VES-\(l)" }
        return "VES · USOAK"
    }

    // MARK: - Top bar (eyebrow + back chevron + title + kebab)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · ACCESSORIAL CHARGES")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("VES · USOAK")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Accessorials")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s4)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: - Hero card (gradient-rim · this-booking + line-count chips · total)

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                // Filter chips: "this booking" · "N line items"
                HStack(spacing: Space.s2) {
                    chip("this booking")
                    chip("\(lineCount) line item\(lineCount == 1 ? "" : "s")")
                }
                // Big gradient total.
                Text(currency(grandTotal))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                    .padding(.top, Space.s4)
            }
            .padding(Space.s4)

            // Top-right: booking ref + billable / disputed counts.
            VStack(alignment: .trailing, spacing: 4) {
                Text(bookingRef)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("\(billableCount) billable")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(disputedCount) disputed")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(disputedCount > 0 ? Brand.warning : palette.textTertiary)
            }
            .padding(Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1.5)
        )
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold)).tracking(0.5)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
    }

    // MARK: - Charge lines · by code

    private var chargeLinesSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CHARGE LINES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("by code")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }

            VStack(spacing: 0) {
                if lines.isEmpty {
                    emptyLedgerRow
                } else {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                        chargeRow(line)
                        if idx < lines.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                    Divider().overlay(palette.borderFaint)
                        .padding(.horizontal, Space.s4)
                    subtotalRow
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func chargeRow(_ line: AccessorialLine731) -> some View {
        let accent = codeAccent(line.code)
        let applied = line.state == .applied
        return HStack(alignment: .top, spacing: Space.s3) {
            // Code-keyed glyph chip.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: codeGlyph(line.code))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(line.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(line.meta)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(applied ? "APPLIED" : "DISPUTED")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(applied ? Brand.success : Brand.warning)
                Text(currency(line.amount))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
            }
        }
        .padding(Space.s4)
    }

    private var subtotalRow: some View {
        HStack {
            Text("Subtotal · \(billableCount) billable")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(currency(billableSubtotal))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private var emptyLedgerRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.textTertiary.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("No accessorial lines")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("approved charges · held disputes appear here by code")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer()
        }
        .padding(Space.s4)
    }

    // MARK: - Apply / Add CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                Task { await applyToInvoice() }
            } label: {
                HStack(spacing: 6) {
                    if applying {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    }
                    Text(applying ? "Applying…" : "Apply to invoice")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(applying || billableCount == 0)
            .opacity(billableCount == 0 ? 0.6 : 1.0)
            .frame(maxWidth: .infinity)

            Button {
                withAnimation(.easeOut(duration: 0.18)) { showCatalog.toggle() }
            } label: {
                Text("Add line")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(minWidth: 124, minHeight: 48)
                    .padding(.horizontal, Space.s3)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Catalog (Add line) — live getAccessorialCatalog

    @ViewBuilder
    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ACCESSORIAL CATALOG · BY CODE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            let items = catalog?.items ?? []
            if items.isEmpty {
                EusoEmptyState(
                    systemImage: "tag",
                    title: "Catalog unavailable",
                    subtitle: "The accessorial code catalog will populate from the tariff schedule.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        catalogRow(item)
                        if idx < items.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func catalogRow(_ item: AccessorialCatalogItem731) -> some View {
        let accent = codeAccent(item.code)
        return Button {
            Task { await applyFromCatalog(item) }
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: codeGlyph(item.code))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        Text(item.code)
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(accent.opacity(0.12)))
                    }
                    Text(catalogMeta(item))
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
                Image(systemName: applying ? "hourglass" : "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(applying ? AnyShapeStyle(palette.textTertiary) : AnyShapeStyle(LinearGradient.diagonal))
            }
            .padding(Space.s4)
        }
        .buttonStyle(.plain)
        .disabled(applying)
    }

    private func catalogMeta(_ item: AccessorialCatalogItem731) -> String {
        var parts: [String] = []
        if let r = item.defaultRate, r > 0 {
            parts.append("\(currency(r))\(item.unit.map { " \($0)" } ?? "")")
        } else if let u = item.unit, !u.isEmpty {
            parts.append(u)
        }
        if let ft = item.freeTime, ft > 0 { parts.append("\(ft) free") }
        if let c = item.category, !c.isEmpty { parts.append(c) }
        return parts.isEmpty ? (item.description ?? item.code) : parts.joined(separator: " · ")
    }

    // MARK: - Banners

    private func ackBanner(_ msg: String) -> some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(msg).font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }

    // MARK: - Code → glyph / accent / title (mirrors the five SVG rows)

    private func chargeCode(for type: String?) -> String {
        let t = (type ?? "").lowercased()
        // Server `type` is sometimes the code itself, sometimes a name.
        switch t {
        case "chc", "chassis", "chassis_split":  return "CHC"
        case "con", "congestion", "port_congestion": return "CON"
        case "rpm", "reefer", "reefer_plugin", "reefer_plug": return "RPM"
        case "exm", "exam", "customs_exam", "vacis": return "EXM"
        case "dem", "demurrage":                  return "DEM"
        case "det", "detention":                  return "DET"
        case "tonu":                              return "TONU"
        case "lay", "layover":                    return "LAY"
        case "stg", "storage":                    return "STG"
        default:
            // If the server handed us a short code, surface it uppercased.
            let raw = (type ?? "CHG")
            return raw.count <= 4 ? raw.uppercased() : String(raw.prefix(3)).uppercased()
        }
    }

    private func chargeTitle(for type: String?) -> String {
        switch chargeCode(for: type) {
        case "CHC":  return "Chassis split"
        case "CON":  return "Port congestion"
        case "RPM":  return "Reefer plug-in"
        case "EXM":  return "Customs exam (VACIS)"
        case "DEM":  return "Demurrage overage"
        case "DET":  return "Detention"
        case "TONU": return "Truck order not used"
        case "LAY":  return "Layover"
        case "STG":  return "Storage"
        default:
            let raw = (type ?? "Accessorial")
            return raw.count <= 4
                ? raw.uppercased() + " charge"
                : raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func codeGlyph(_ code: String) -> String {
        switch code {
        case "CHC":  return "truck.box.fill"
        case "CON":  return "water.waves"
        case "RPM":  return "thermometer.snowflake"
        case "EXM":  return "magnifyingglass"
        case "DEM":  return "clock.fill"
        case "DET":  return "clock.badge.exclamationmark"
        case "STG":  return "shippingbox.fill"
        default:     return "dollarsign.circle.fill"
        }
    }

    private func codeAccent(_ code: String) -> Color {
        switch code {
        case "CHC":  return Brand.rail                 // slate (chassis)
        case "CON":  return Brand.warning              // amber (congestion)
        case "RPM":  return Brand.blue                 // reefer
        case "EXM":  return Brand.magenta              // customs
        case "DEM", "DET": return Brand.danger         // time-overage
        default:     return Brand.vessel
        }
    }

    // MARK: - Per-row meta lines

    private func appliedMeta(_ row: AccessorialBillingRow731) -> String {
        var parts: [String] = [chargeCode(for: row.type)]
        if let f = row.facilityName, !f.isEmpty, f != "N/A" {
            parts.append(f)
        } else if let o = row.origin, !o.isEmpty, o != "N/A" {
            parts.append(o)
        } else {
            parts.append("USOAK")
        }
        if let s = row.status, !s.isEmpty { parts.append(s.lowercased()) }
        return parts.joined(separator: " · ")
    }

    private func disputedMeta(_ row: AccessorialDisputeRow731) -> String {
        var parts: [String] = [chargeCode(for: row.type)]
        if let r = row.reason, !r.isEmpty, r != "N/A" {
            parts.append(r.count > 28 ? String(r.prefix(28)) + "…" : r)
        } else {
            parts.append("held · under review")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Formatting

    private func currency(_ v: Double) -> String {
        if v == v.rounded() {
            return "$\(Int(v).formatted(.number.grouping(.automatic)))"
        }
        return "$\(String(format: "%.2f", v))"
    }

    // MARK: - Loading skeleton

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 96)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 360)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Load (billing + disputes + catalog in parallel)

    private func load() async {
        loading = true; loadError = nil
        struct BillingIn: Encodable { let status: String; let batchSize: Int }
        struct DisputesIn: Encodable { let limit: Int }
        do {
            async let bill: AccessorialBilling731 = EusoTripAPI.shared.query(
                "detentionAccessorials.getAccessorialBilling",
                input: BillingIn(status: "approved", batchSize: 50))
            async let disp: AccessorialDisputes731 = EusoTripAPI.shared.query(
                "detentionAccessorials.getAccessorialDisputes",
                input: DisputesIn(limit: 50))
            async let cat: AccessorialCatalog731 = EusoTripAPI.shared.queryNoInput(
                "detentionAccessorials.getAccessorialCatalog")

            let (billingResp, disputesResp, catalogResp) = try await (bill, disp, cat)
            self.billing = billingResp
            self.disputes = disputesResp
            self.catalog = catalogResp
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Apply to invoice (re-applies the billable lines for this booking)
    //
    // applyAccessorial writes ONE charge row at a time keyed to {loadId,
    // chargeCode, amount}. The CTA needs a bound load to write against; when
    // unbound (ScreenRegistry mount, no booking selected) we surface the real
    // gap honestly rather than faking a success toast.

    private func applyToInvoice() async {
        applyAck = nil; applyError = nil
        let target = boundLoadId
        guard target > 0 else {
            applyError = "Open a vessel booking to apply its accessorial lines to an invoice."
            return
        }
        guard !appliedLines.isEmpty else {
            applyError = "No billable lines to apply."
            return
        }
        applying = true
        struct ApplyIn: Encodable {
            let loadId: Int
            let chargeCode: String
            let amount: Double
            let description: String
            let quantity: Int
        }
        var applied = 0
        var firstError: String? = nil
        for line in appliedLines where line.amount > 0 {
            let input = ApplyIn(
                loadId: target,
                chargeCode: line.code,
                amount: line.amount,
                description: "\(line.title) — invoiced from accessorial ledger",
                quantity: 1)
            do {
                let res: ApplyAccessorialResult731 = try await EusoTripAPI.shared.mutation(
                    "detentionAccessorials.applyAccessorial", input: input)
                if res.success == true { applied += 1 }
            } catch {
                if firstError == nil {
                    firstError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
        if applied > 0 {
            applyAck = "Applied \(applied) billable line\(applied == 1 ? "" : "s") · \(currency(billableSubtotal)) to invoice."
            await load()
        }
        if let firstError, applied == 0 {
            applyError = firstError
        }
        applying = false
    }

    private func applyFromCatalog(_ item: AccessorialCatalogItem731) async {
        applyAck = nil; applyError = nil
        let target = boundLoadId
        guard target > 0 else {
            applyError = "Open a vessel booking to add a \(item.code) line to its invoice."
            return
        }
        guard let rate = item.defaultRate, rate > 0 else {
            applyError = "\(item.name) has no default rate — configure the tariff rate first."
            return
        }
        applying = true
        struct ApplyIn: Encodable {
            let loadId: Int
            let chargeCode: String
            let amount: Double
            let description: String
            let quantity: Int
        }
        let input = ApplyIn(
            loadId: target,
            chargeCode: item.code,
            amount: rate,
            description: item.description ?? item.name,
            quantity: 1)
        do {
            let res: ApplyAccessorialResult731 = try await EusoTripAPI.shared.mutation(
                "detentionAccessorials.applyAccessorial", input: input)
            if res.success == true {
                applyAck = "Added \(item.name) (\(item.code)) · \(currency(rate)) to the ledger."
                await load()
            } else {
                applyError = "\(item.name) did not confirm. Try again."
            }
        } catch {
            applyError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        applying = false
    }

    /// Resolve the load to write against: the injected booking, else the load
    /// the existing billable/disputed lines belong to.
    private var boundLoadId: Int {
        if loadId > 0 { return loadId }
        if let l = billing?.pendingCharges.first?.loadId, l > 0 { return l }
        if let l = disputes?.disputes.first?.loadId, l > 0 { return l }
        return 0
    }
}

#Preview("731 · Vessel Accessorial Charges · Night") { VesselAccessorialChargesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("731 · Vessel Accessorial Charges · Light") { VesselAccessorialChargesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
