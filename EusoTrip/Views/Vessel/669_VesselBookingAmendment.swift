//
//  669_VesselBookingAmendment.swift
//  EusoTrip — Vessel Operator · Booking Amendment
//
//  Bespoke port of "06 Vessel/Light-SVG/669 Vessel Booking Amendment.svg" (+ Dark),
//  reconstructed to the flagship FORM/amendment WORK-SURFACE grammar the registered
//  vessel siblings ship (664 Terminal Appointment / 680 Intermodal Segment Board /
//  757 Detention Letters): back chevron + ✦ eyebrow + caption + 28/-0.4 title ->
//  gradient-rim hero ActiveCard (fields-changed count + route) -> 3-cell KPI strip
//  (cell 1 = LinearGradient.diagonal) -> itemized icon-chip change ledger (40x40 chip +
//  title + mono before→after sub + SHORT status pill) -> amendment-history strip ->
//  ESang advisory row -> CTA pair (Propose to carrier / Discard). Shipments slot inked
//  (this is a booking-ops / amendment surface, not a D&D/compliance one) on the real
//  Vessel Operator BottomNav (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME).
//
//  Data / wiring (endpoint confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    bookingAmendment.amendmentHistory (EXISTS frontend/server/routers/bookingAmendment.ts:92 ·
//      query · input {shipmentId} · returns [{eventType:"amendment_proposed|approved|rejected",
//      timestamp, parsedDetails:{amendmentId,reason,diff,appliedChanges,...}}] from
//      vesselShipmentEvents WHERE eventType LIKE 'amendment_%' ORDER BY timestamp DESC).
//      The hero counts (changes / approved / rejected) + the change ledger + the history
//      strip all render from this live history. Empty history => the bespoke empty state
//      renders honestly (no fabricated diff rows).
//    "Propose to carrier" -> bookingAmendment.proposeAmendment (EXISTS :16 · mutation,
//      input {shipmentId, changes, reason}) — STUB · named-gap here: this surface has no
//      editable field controls (the SVG shows a fixed read-only diff), so there is no user
//      `changes` payload to send. Wiring a faked hardcoded diff would be dishonest; instead
//      the verb is flagged STUB and re-runs load() (the surfaced gap is the field-editor UI
//      this screen would need to compose a real `changes` map). "Discard" re-runs load().
//
//  0 mock data on load · honest empty/error states. All file-scoped helper types are
//  suffixed 669 to avoid cross-file private-type collisions. RimCard669 / ESangRow669 /
//  the secondary outline button mirror 757's file-private grammar (RimCard/ESangRow/
//  SecondaryButton are not shared app symbols). The wired query takes a real
//  {shipmentId} input (HistoryIn669), so no module-level EmptyInput is needed.
//

import SwiftUI

// MARK: - Change ledger / history model

private enum AmendKind669 { case proposed, approved, rejected, other
    var pill: String { switch self { case .proposed: "CHANGED"; case .approved: "APPROVED"; case .rejected: "REJECTED"; case .other: "EVENT" } }
    var tint: Color { switch self {
        case .proposed: Brand.blue
        case .approved: Brand.success
        case .rejected: Brand.danger
        case .other:    Brand.neutral }
    }
    var glyph: String { switch self {
        case .proposed: "arrow.left.arrow.right"
        case .approved: "checkmark.seal"
        case .rejected: "xmark.seal"
        case .other:    "doc.text" }
    }
    static func from(_ raw: String?) -> AmendKind669 {
        switch raw ?? "" {
        case "amendment_proposed": return .proposed
        case "amendment_approved": return .approved
        case "amendment_rejected": return .rejected
        default:                   return .other
        }
    }
}

private struct AmendRow669: Identifiable {
    let id = UUID()
    let kind: AmendKind669
    let title: String   // amendment id
    let sub: String     // reason / applied-fields summary
}

// MARK: - Wrapper (registry expects Vessel<...>Screen)

struct VesselBookingAmendmentScreen: View {
    let theme: Theme.Palette
    /// Confirmed booking under amendment. Defaults to the canonical
    /// CNSHA→USLGB · ONE context shipment.
    var shipmentId: Int = 1
    init(theme: Theme.Palette, shipmentId: Int = 1) { self.theme = theme; self.shipmentId = shipmentId }

    var body: some View {
        Shell(theme: theme) {
            VesselBookingAmendmentBody(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselBookingAmendmentBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var proposing = false

    @State private var rows: [AmendRow669] = []
    @State private var nChanges = 0
    @State private var nApproved = 0
    @State private var nRejected = 0
    @State private var latestReason: String? = nil

    private var hasHistory: Bool { !rows.isEmpty }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading amendment history…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if !hasHistory {
                    EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                                   title: "No amendments yet",
                                   subtitle: "amendmentHistory returned an empty ledger for this booking — nothing has been proposed, approved, or rejected. Propose a change to start the trail.")
                    ctaRow
                } else {
                    hero
                    kpiStrip
                    changeLedger
                    if let reason = latestReason {
                        Text("reason: \(reason)").font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    }
                    historyStrip
                    ESangRow669(title: esangTitle, subtitle: esangSubtitle)
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · AMENDMENT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("VES · CONF").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Text("Amend booking").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Text("amendmentHistory · CNSHA → USLGB · ONE").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Hero (gradient-rim)

    private var hero: some View {
        RimCard669 {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(nChanges)").font(.system(size: 34, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                    Text(nChanges == 1 ? "amendment on record" : "amendments on record").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Text("vs confirmed booking").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ROUTE").font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    Text("CNSHA").font(.system(size: 22, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text("to USLGB · ONE").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: 8) {
            statTile("CHANGES",  "\(nChanges)",  gradient: true)
            statTile("APPROVED", "\(nApproved)", tint: Brand.success)
            statTile("REJECTED", "\(nRejected)", tint: Brand.danger)
        }
    }

    private func statTile(_ label: String, _ value: String, gradient: Bool = false, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(gradient ? Color.white.opacity(0.85) : palette.textTertiary)
            Group {
                if gradient { Text(value).foregroundStyle(.white) }
                else if let tint { Text(value).foregroundStyle(tint) }
                else { Text(value).foregroundStyle(palette.textPrimary) }
            }
            .font(.system(size: 22, weight: .semibold)).monospacedDigit()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(gradient ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
        )
    }

    // MARK: Change ledger (itemized icon-chip rows)

    private var changeLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("AMENDMENT LEDGER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("bookingAmendment.ts:92").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            ForEach(rows) { ledgerRow($0) }
        }
    }

    private func ledgerRow(_ r: AmendRow669) -> some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(r.kind.tint.opacity(0.14)).frame(width: 40, height: 40)
                    Image(systemName: r.kind.glyph).font(.system(size: 16, weight: .semibold)).foregroundStyle(r.kind.tint)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(r.sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Text(r.kind.pill).font(.system(size: 11, weight: .bold)).kerning(0.5).foregroundStyle(r.kind.tint)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(r.kind.tint.opacity(0.16)))
            }
        }
    }

    // MARK: History strip

    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AMENDMENT HISTORY").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("amendmentHistory").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Text("\(nApproved) approved · \(nRejected) rejected · \(nChanges - nApproved - nRejected) pending").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            Text("ordered newest-first from vesselShipmentEvents").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
    }

    // MARK: CTA pair

    private var ctaRow: some View {
        HStack(spacing: 8) {
            CTAButton(title: proposing ? "Proposing…" : "Propose to carrier",
                      action: { Task { await propose() } },
                      trailingIcon: "paperplane",
                      isLoading: proposing)
            secondaryButton(title: "Discard") { Task { await load() } }
                .frame(width: 132)
        }
    }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so this hand-rolls the same outline grammar the
    /// registered siblings (757 `secondaryButton`) use for their secondary CTA.
    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: ESang advisory

    private var esangTitle: String {
        if nRejected > 0 { return "ESang: \(nRejected) amendment\(nRejected == 1 ? "" : "s") were rejected by the carrier" }
        if nApproved > 0 { return "ESang: \(nApproved) amendment\(nApproved == 1 ? "" : "s") approved — booking is current" }
        return "ESang: amendment proposed, awaiting carrier"
    }
    private var esangSubtitle: String {
        if nRejected > 0 { return "re-propose with the carrier's counter, or revert to the confirmed booking" }
        if nApproved > 0 { return "no open changes — the confirmed booking matches the amendment" }
        return "the carrier has not yet approved or rejected this change"
    }

    // MARK: Load + mutate

    private func load() async {
        loading = true; loadError = nil
        struct HistoryIn669: Encodable { let shipmentId: Int }
        struct Details669: Decodable {
            let amendmentId: String?
            let reason: String?
            let appliedChanges: [String]?
        }
        struct Event669: Decodable {
            let eventType: String?
            let parsedDetails: Details669?
        }
        do {
            let events: [Event669] = try await EusoTripAPI.shared.query(
                "bookingAmendment.amendmentHistory",
                input: HistoryIn669(shipmentId: shipmentId))
            var proposed = 0, approved = 0, rejected = 0
            var firstReason: String? = nil
            rows = events.map { e in
                let kind = AmendKind669.from(e.eventType)
                switch kind {
                case .proposed: proposed += 1
                case .approved: approved += 1
                case .rejected: rejected += 1
                case .other:    break
                }
                let d = e.parsedDetails
                if firstReason == nil, let r = d?.reason, !r.isEmpty { firstReason = r }
                let sub: String
                switch kind {
                case .approved:
                    let fields = d?.appliedChanges ?? []
                    sub = fields.isEmpty ? "applied to booking" : "applied: \(fields.joined(separator: ", "))"
                case .rejected:
                    sub = d?.reason.map { "rejected · \($0)" } ?? "rejected by carrier"
                case .proposed:
                    sub = d?.reason ?? "proposed to carrier"
                case .other:
                    sub = e.eventType ?? "event"
                }
                return AmendRow669(kind: kind, title: d?.amendmentId ?? "AMD-\(shipmentId)", sub: sub)
            }
            nChanges = rows.count
            nApproved = approved
            nRejected = rejected
            latestReason = firstReason
            _ = proposed
        } catch {
            rows = []; nChanges = 0; nApproved = 0; nRejected = 0; latestReason = nil
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// proposeAmendment (frontend/server/routers/bookingAmendment.ts:16) is a real
    /// mutation, but this surface composes no editable-field controls (the SVG shows a
    /// fixed read-only diff), so there is no honest user `changes` map to send. Flagged
    /// STUB · named-gap (the field-editor UI is the surfaced backend-adjacent gap) and
    /// re-runs load() rather than POST a fabricated diff.
    private func propose() async {
        proposing = true
        await load()
        proposing = false
    }
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// Gradient-rim hero card — mirrors the gradient-stroked context cards the
/// registered siblings (664 `moveContextCard`, 757 `RimCard757`) ship.
private struct RimCard669<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
    }
}

/// ESang advisory row — the canonical port's `ESangRow` is not a shared app
/// symbol, so this renders the same sparkle + advisory grammar file-scoped.
private struct ESangRow669: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }
}

#Preview("669 · Vessel Booking Amendment · Night") {
    VesselBookingAmendmentScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("669 · Vessel Booking Amendment · Light") {
    VesselBookingAmendmentScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
