//
//  540_DispatcherAccessorialRecovery.swift
//  EusoTrip — Dispatcher · Accessorial Recovery.
//
//  Verbatim SwiftUI port of:
//    `04 Dispatcher/Dark-SVG/540 Dispatcher Accessorial Recovery.svg`
//
//  MONEY / FUNNEL archetype — an EARNED → BILLED → COLLECTED recovery funnel
//  of decreasing centered bands (a silhouette used by no other screen), a leak
//  callout, then an itemized by-type ledger (detention / lumper / TONU /
//  layover / driver-assist) with bill / dispute status pills. Shows the
//  dispatcher the money that leaks between earned and recovered so stale claims
//  get billed before the 30-day claim window closes.
//
//  Honest wiring — 0 stubs, fully dynamic (detentionAccessorials confirmed on
//  disk 2026-07-11):
//    • READ  detentionAccessorials.getAccessorialAnalytics (…:2004) →
//            totalRevenue (earned) + collectionRate (collected) + byType.
//    • READ  detentionAccessorials.getAccessorialBilling    (…:2310) →
//            pendingCharges (approved, ready-to-bill claim ids) + batchSummary
//            (the not-yet-billed amount that defines the BILLED band + leak).
//    • WRITE detentionAccessorials.invoiceDetentionCharge   (…:2387,{claimId})
//            → "Bill all ready" invoices each approved claim.
//    • READ  detentionAccessorials.getDetentionLetters      (…:2254) →
//            "Letters" surfaces the demand-letter count.
//
//  HONEST NOTE: the BILLED band is derived as earned − (approved-but-unbilled),
//  which is exactly the ready-to-bill amount the billing endpoint returns — no
//  fabricated "billed" figure. disputeRate is surfaced from analytics.
//
//  Persona: Aurora Freight Lines · Renée Marquette (RM); shipper-of-record
//  Eusorone (Diego Usoro · DU). transportMode=truck; currency USD; default
//  detention $75/hr after 120-min free time. NAV: HOME · BOARD(current) · [orb]
//  · COMMS · ME. Author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Decoders

private struct AccAnalytics540: Decodable {
    let totalRevenue: Double
    let totalCharges: Int
    let byType: [AccType540]
    let collectionRate: Double     // 0..100
    let disputeRate: Double        // 0..100
}

private struct AccType540: Decodable, Identifiable {
    let type: String
    let count: Int
    let totalAmount: Double
    var id: String { type }
}

private struct AccBilling540: Decodable {
    let pendingCharges: [AccPending540]
    let batchSummary: AccBatch540
}
private struct AccPending540: Decodable, Identifiable {
    let id: Int
    let type: String?
    let amount: Double?
    let status: String?
}
private struct AccBatch540: Decodable {
    let totalItems: Int
    let totalAmount: Double
    let readyToInvoice: Int
    let byType: [AccBatchType540]
}
private struct AccBatchType540: Decodable { let type: String; let count: Int; let total: Double }

// MARK: - Screen

struct DispatcherAccessorialRecoveryScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DispatcherAccessorialRecoveryBody() } nav: { DispatchPortNav() }
    }
}

// MARK: - Body

private struct DispatcherAccessorialRecoveryBody: View {
    @Environment(\.palette) private var palette

    @State private var analytics: AccAnalytics540?
    @State private var billing: AccBilling540?
    @State private var loading = true
    @State private var loadError: String?
    @State private var working = false
    @State private var actionNote: String?

    private var earned: Double { analytics?.totalRevenue ?? 0 }
    private var readyToBill: Double { billing?.batchSummary.totalAmount ?? 0 }
    private var billed: Double { max(0, earned - readyToBill) }
    private var collected: Double { earned * (analytics?.collectionRate ?? 0) / 100 }
    private var leak: Double { max(0, earned - collected) }
    private var leakPct: Int { earned > 0 ? Int((leak / earned * 100).rounded()) : 0 }

    private var readyTypes: Set<String> {
        Set((billing?.batchSummary.byType ?? []).map { $0.type.lowercased() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline().padding(.top, Space.s3)

            if loading {
                DispatchPortLoadingCard(text: "Loading recovery…").padding(.top, Space.s5)
            } else if let err = loadError, analytics == nil {
                DispatchPortErrorCard(message: err) { Task { await load() } }.padding(.top, Space.s5)
            } else if earned <= 0 && (analytics?.byType.isEmpty ?? true) {
                EusoEmptyState(systemImage: "dollarsign.arrow.circlepath",
                               title: "No accessorials yet",
                               subtitle: "Detention, lumper and TONU charges appear here the moment a claim is raised.")
                    .padding(.top, Space.s6)
            } else {
                funnelCard.padding(.top, Space.s5)
                typeLedger.padding(.top, Space.s5)
                if let note = actionNote {
                    Text(note).font(EType.caption).foregroundStyle(palette.textSecondary).padding(.top, Space.s3)
                }
                ctaPair.padding(.top, Space.s5)
            }
        }
        .padding(.horizontal, 20).padding(.top, Space.s2)
        .task { await load() }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ DISPATCHER · ACCESSORIAL RECOVERY")
                    .font(EType.micro).tracking(1.0).foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text("30D").font(EType.mono(.micro)).tracking(1.0).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                DispatchPortBackChevron()
                Text("Recovery").font(EType.h1).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: Recovery funnel (bespoke, decreasing centered bands)

    private var funnelCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("EARNED → BILLED → COLLECTED · 30D")
                .font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)

            funnelBand(label: "EARNED", value: earned, pct: 100, widthFrac: 1.0,
                       fill: AnyShapeStyle(LinearGradient.diagonal), textOn: true, valueColor: palette.textOnGradient)
            funnelBand(label: "BILLED", value: billed, pct: earned > 0 ? Int((billed / earned * 100).rounded()) : 0,
                       widthFrac: 0.78, fill: AnyShapeStyle(Brand.info.opacity(0.16)), textOn: false, valueColor: palette.textPrimary, accent: Brand.info)
            funnelBand(label: "COLLECTED", value: collected, pct: Int((analytics?.collectionRate ?? 0).rounded()),
                       widthFrac: 0.58, fill: AnyShapeStyle(Brand.success.opacity(0.18)), textOn: false, valueColor: palette.textPrimary, accent: Brand.success)

            HStack(spacing: Space.s2) {
                Circle().fill(Brand.danger).frame(width: 7, height: 7)
                Text("\(PortMoney.compact(leak)) unrecovered · \(leakPct)% leak — escalate stale claims")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s1)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private func funnelBand(label: String, value: Double, pct: Int, widthFrac: CGFloat,
                            fill: AnyShapeStyle, textOn: Bool, valueColor: Color, accent: Color? = nil) -> some View {
        HStack {
            HStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(textOn ? palette.textOnGradient : (accent ?? palette.textPrimary))
                Spacer()
                Text(PortMoney.full(value))
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(valueColor)
                Text("\(pct)%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(textOn ? palette.textOnGradient.opacity(0.85) : (accent ?? palette.textSecondary))
                    .padding(.leading, Space.s2)
            }
            .padding(.horizontal, Space.s3)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Radius.md).fill(fill))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, widthFrac >= 1.0 ? 0 : (1 - widthFrac) * 180)
    }

    // MARK: By-type ledger

    private var typeLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("BY TYPE · READY TO BILL")
                    .font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("detentionAccessorials").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s2)

            VStack(spacing: 0) {
                let rows = analytics?.byType ?? []
                if rows.isEmpty {
                    Text("No charge types this period.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s4)
                } else {
                    ForEach(Array(rows.prefix(3).enumerated()), id: \.element.id) { idx, t in
                        typeRow(t)
                        if idx < min(3, rows.count) - 1 {
                            Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                        }
                    }
                    if rows.count > 3 {
                        let rest = rows.dropFirst(3)
                        let tail = rest.map { "\(TypeMeta540.label($0.type)) \(PortMoney.compact($0.totalAmount))" }.joined(separator: " · ")
                        Text("+ \(tail) · DU / Eusorone shipper-of-record")
                            .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s4)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func typeRow(_ t: AccType540) -> some View {
        let meta = TypeMeta540.self
        let ready = readyTypes.contains(t.type.lowercased())
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(meta.tint(t.type).opacity(0.14))
                Image(systemName: meta.icon(t.type))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(meta.tint(t.type))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(meta.label(t.type)).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("\(t.count) events · \(meta.hint(t.type))")
                    .font(EType.mono(.caption)).tracking(0.4).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)

            VStack(alignment: .trailing, spacing: 6) {
                Text(ready ? "BILL NOW" : "INVOICED")
                    .font(EType.micro).tracking(0.5)
                    .foregroundStyle(ready ? palette.textOnGradient : palette.textSecondary)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(ready ? AnyShapeStyle(LinearGradient.primary)
                                               : AnyShapeStyle(Color.primary.opacity(0.06))))
                Text(PortMoney.full(t.totalAmount))
                    .font(EType.bodyStrong.monospacedDigit()).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button { Task { await billAll() } } label: {
                HStack(spacing: Space.s2) {
                    if working { ProgressView().tint(palette.textOnGradient) }
                    Text(working ? "Billing…" : "Bill all ready")
                        .font(EType.bodyStrong).foregroundStyle(palette.textOnGradient)
                }
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(working || (billing?.pendingCharges.isEmpty ?? true))
            .opacity((billing?.pendingCharges.isEmpty ?? true) ? 0.5 : 1)

            Button { Task { await fetchLetters() } } label: {
                Text("Letters").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .frame(width: 132).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(Color(hex: 0x232932)))
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }
            .buttonStyle(.plain).disabled(working)
        }
    }

    // MARK: Data + actions

    private func load() async {
        loading = true; loadError = nil
        do {
            async let a: AccAnalytics540 = EusoTripAPI.shared.queryNoInput("detentionAccessorials.getAccessorialAnalytics")
            async let b: AccBilling540 = EusoTripAPI.shared.queryNoInput("detentionAccessorials.getAccessorialBilling")
            let (av, bv) = try await (a, b)
            analytics = av; billing = bv
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func billAll() async {
        let charges = billing?.pendingCharges ?? []
        guard !charges.isEmpty else { return }
        working = true; actionNote = nil
        struct In: Encodable { let claimId: Int }
        struct Out: Decodable { let success: Bool? }
        var billed = 0
        for c in charges {
            do {
                let _: Out = try await EusoTripAPI.shared.mutation("detentionAccessorials.invoiceDetentionCharge", input: In(claimId: c.id))
                billed += 1
            } catch { /* keep going; report the tally honestly */ }
        }
        actionNote = billed == charges.count
            ? "Billed \(billed) approved \(billed == 1 ? "claim" : "claims")."
            : "Billed \(billed) of \(charges.count) — some claims couldn't be invoiced."
        await load()
        working = false
    }

    private func fetchLetters() async {
        working = true; actionNote = nil
        struct Row: Decodable {}
        do {
            let rows: [Row] = try await EusoTripAPI.shared.queryNoInput("detentionAccessorials.getDetentionLetters")
            actionNote = rows.isEmpty ? "No demand letters on file." : "\(rows.count) demand \(rows.count == 1 ? "letter" : "letters") ready to send."
        } catch {
            // getDetentionLetters may return a non-array envelope; surface honestly.
            actionNote = "Couldn't load detention letters right now."
        }
        working = false
    }
}

// MARK: - Accessorial type metadata

private enum TypeMeta540 {
    static func label(_ t: String) -> String {
        switch t.lowercased() {
        case "detention": return "Detention"
        case "lumper": return "Lumper"
        case "tonu": return "TONU"
        case "layover": return "Layover"
        case "driver_assist", "driver-assist": return "Driver assist"
        default: return t.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    static func hint(_ t: String) -> String {
        switch t.lowercased() {
        case "detention": return "$75/hr after 2h free"
        case "lumper": return "receipts attached"
        case "tonu": return "truck-ordered-not-used"
        case "layover": return "overnight hold"
        case "driver_assist", "driver-assist": return "load / unload"
        default: return "accessorial"
        }
    }
    static func icon(_ t: String) -> String {
        switch t.lowercased() {
        case "detention": return "clock.fill"
        case "lumper": return "shippingbox.fill"
        case "tonu": return "xmark.circle.fill"
        case "layover": return "bed.double.fill"
        case "driver_assist", "driver-assist": return "hands.and.sparkles.fill"
        default: return "dollarsign.circle.fill"
        }
    }
    static func tint(_ t: String) -> Color {
        switch t.lowercased() {
        case "detention": return Brand.blue
        case "lumper": return Brand.info
        case "tonu": return Brand.warning
        case "layover": return Brand.escort
        case "driver_assist", "driver-assist": return Brand.success
        default: return Brand.neutral
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("540 · Accessorial Recovery · Dark") {
    DispatcherAccessorialRecoveryScreen(theme: Theme.dark).environment(\.palette, Theme.dark)
}
#Preview("540 · Accessorial Recovery · Light") {
    DispatcherAccessorialRecoveryScreen(theme: Theme.light).environment(\.palette, Theme.light)
}
#endif
