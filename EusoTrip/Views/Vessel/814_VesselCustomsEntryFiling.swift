//
//  814_VesselCustomsEntryFiling.swift
//  EusoTrip — Vessel Operator · Customs Entry Filing.
//
//  Faithful 1:1 port of the RECONSTRUCTED "814 Vessel Customs Entry Filing.svg" (Light + Dark),
//  adapted into the registered vessel app convention (Shell + vessel BottomNav, COMPLIANCE inked —
//  the same wrapper the registered sibling 757 ships).
//  RECONSTRUCTED from the post-cadence-line STAMP (gradient stat hero + 3-cell KPI strip +
//  uniform chip rows) into the FILING-FORM archetype: a declared-value summary hero with the
//  computed ad-valorem duty, then the 7501 broken out as label-over-value FORM FIELD rows grouped
//  DECLARATION / VALUATION + BROKER. Nav anchored to VesselOperatorNavController
//  (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME).
//
//  ZERO-FALLBACK (2026-06-09 · B20 fix): the previous build rendered a fully FABRICATED 7501
//  ($184,200 declared · HTS 8517.62.0090 · CN origin · broker #318 · shipment 4471) and its CTAs
//  fired REAL createCustomsEntry/updateCustomsStatus mutations — writing invented customs data
//  into prod customsDeclarations + the blockchainAuditTrail with one tap. Now:
//    READ  (live): vesselShipments.getCustomsEntries EXISTS :2062 — newest-first raw
//        customsDeclarations rows (DECIMAL columns serialize as JSON strings). The screen
//        hydrates the newest DRAFT entry (scoped to `shipmentId` when threaded) and renders
//        every field from it — em-dash for any absent value, honest empty state when no draft.
//    FILE  (write): vesselShipments.updateCustomsStatus EXISTS :693 — transitions the HYDRATED
//        draft to "filed" (sets filedDate server-side, :706). The CTA is hard-DISABLED unless a
//        real draft row with real shipmentId + declaredValue + HTS + origin + duty rate is live.
//    NO createCustomsEntry is fired from this screen anymore — there is no operator input form
//        here, so minting new declarations from display state was the fabrication vector.
//        "Save draft" stays in the layout but is permanently disabled with an honest hint until
//        an edit form exists (composing happens in the booking flow).
//
//  RimCard814 / secondaryButton814 are file-scoped bespoke helpers (the canonical port's RimCard /
//  SecondaryButton are not shared app symbols), built from the same gradient-rim grammar sibling
//  757 uses, to preserve the exact wireframe look.
//

import SwiftUI

struct VesselCustomsEntryFilingScreen: View {
    let theme: Theme.Palette
    /// Vessel shipment the 7501 scopes to. nil (registry/zero-arg use) hydrates the
    /// operator's newest draft declaration across shipments.
    var shipmentId: Int? = nil
    init(theme: Theme.Palette, shipmentId: Int? = nil) { self.theme = theme; self.shipmentId = shipmentId }
    var body: some View {
        Shell(theme: theme) {
            VesselCustomsEntryFilingBody(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire shape (raw customsDeclarations row · DECIMALs arrive as JSON strings)

private struct CustomsEntryRow814: Decodable {
    let id: Int
    let shipmentId: Int?
    let declarationType: String?
    let entryNumber: String?
    let htsCode: String?
    let countryOfOrigin: String?
    let declaredValue: String?     // DECIMAL → JSON string
    let currency: String?
    let dutyRate: String?          // DECIMAL → JSON string (fraction, e.g. "0.0280")
    let dutyAmount: String?        // DECIMAL → JSON string
    let brokerId: Int?
    let filedDate: String?
    let status: String?            // draft | filed | under_review | cleared | held | rejected
    let createdAt: String?
}

private struct FormField814: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let mono: Bool
    var detail: String? = nil
    var pill: (String, StatusPill.Kind)? = nil
    var trailing: String? = nil
    var chevron: Bool = false
    var editGlyph: Bool = false
}

private struct VesselCustomsEntryFilingBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int?

    @State private var entry: CustomsEntryRow814? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var submitting = false
    @State private var fileDone = false

    // MARK: Derived (every cell reads the hydrated row — em-dash when absent)

    private var declaredValueNum: Double { Double(entry?.declaredValue ?? "") ?? 0 }
    private var dutyRateNum: Double { Double(entry?.dutyRate ?? "") ?? 0 }
    private var dutyAmountNum: Double {
        if let d = Double(entry?.dutyAmount ?? ""), d > 0 { return d }
        // Mirror the server: dutyAmount = declaredValue × dutyRate (createCustomsEntry :661).
        return declaredValueNum > 0 && dutyRateNum > 0 ? declaredValueNum * dutyRateNum : 0
    }
    private var declaredValueLabel: String { declaredValueNum > 0 ? "$" + numberFmt(declaredValueNum) : "—" }
    private var estDutyLabel: String { dutyAmountNum > 0 ? "$" + numberFmt(dutyAmountNum) : "—" }
    private var dutyRateLabel: String { dutyRateNum > 0 ? String(format: "%.1f%% ad valorem", dutyRateNum * 100) : "—" }

    private var statusLabel: String { (entry?.status ?? "draft").replacingOccurrences(of: "_", with: " ").uppercased() }
    private var statusKind: StatusPill.Kind {
        switch (entry?.status ?? "").lowercased() {
        case "filed", "cleared": return .success
        case "held", "rejected": return .danger
        case "under_review":     return .warning
        default:                 return .info
        }
    }

    private var subline: String {
        guard let e = entry else { return "No draft 7501 on file" }
        var parts: [String] = []
        parts.append(e.entryNumber?.isEmpty == false ? "Entry \(e.entryNumber!)" : "Declaration #\(e.id)")
        parts.append((e.declarationType ?? "—").replacingOccurrences(of: "_", with: " "))
        if let s = e.shipmentId, s > 0 { parts.append("shipment \(s)") }
        return parts.joined(separator: " · ")
    }

    private var heroSub: String {
        guard let e = entry else { return "—" }
        var parts: [String] = []
        if let s = e.shipmentId, s > 0 { parts.append("shipment \(s)") }
        parts.append(dutyRateNum > 0 ? String(format: "%.1f%% ad valorem", dutyRateNum * 100) : "duty rate —")
        parts.append((e.currency?.isEmpty == false ? e.currency! : "USD"))
        return parts.joined(separator: " · ")
    }

    private var declarationFields: [FormField814] {
        let e = entry
        let declType: String = {
            switch (e?.declarationType ?? "").lowercased() {
            case "import":           return "Import"
            case "export":           return "Export"
            case "transit":          return "Transit"
            case "temporary_import": return "Temporary import"
            default:                 return "—"
            }
        }()
        return [
            FormField814(label: "DECLARATION TYPE", value: declType, mono: false),
            FormField814(label: "HTS CODE",
                         value: e?.htsCode?.isEmpty == false ? e!.htsCode! : "—",
                         mono: true,
                         pill: e?.htsCode?.isEmpty == false ? ("CLASSIFIED", .info) : nil),
            FormField814(label: "COUNTRY OF ORIGIN",
                         value: e?.countryOfOrigin?.isEmpty == false ? e!.countryOfOrigin! : "—",
                         mono: false)
        ]
    }

    private var valuationFields: [FormField814] {
        let e = entry
        return [
            FormField814(label: "DECLARED VALUE",
                         value: declaredValueNum > 0
                            ? "$" + numberFmt(declaredValueNum) + " " + (e?.currency ?? "USD")
                            : "—",
                         mono: true),
            FormField814(label: "DUTY RATE", value: dutyRateLabel, mono: false,
                         trailing: dutyRateNum > 0 ? "duty = value × rate" : nil),
            FormField814(label: "CUSTOMS BROKER",
                         value: (e?.brokerId).map { "Broker #\($0)" } ?? "—",
                         mono: false,
                         pill: e?.brokerId != nil ? ("ASSIGNED", .success) : nil)
        ]
    }

    /// B20 gate: "File entry with CBP" may only fire on a live DRAFT row whose
    /// declaration is materially complete — every field real, none invented.
    private var canFile: Bool {
        guard let e = entry else { return false }
        return (e.status ?? "draft").lowercased() == "draft"
            && (e.shipmentId ?? 0) > 0
            && declaredValueNum > 0
            && (e.htsCode?.isEmpty == false)
            && (e.countryOfOrigin?.isEmpty == false)
            && dutyRateNum > 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Draft 7501 entry").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if entry == nil {
                    EusoEmptyState(systemImage: "doc.badge.plus",
                                   title: "No draft 7501 on file",
                                   subtitle: "Declarations composed in the booking flow appear here for review and CBP filing. Nothing fabricated, nothing to file yet.")
                } else {
                    // COUNTRY-DONE (814): entry instrument by import country.
                    // US active (CBP 7501 live below); CA/MX standby until
                    // vessel.getEntryRegime lands (named gap).
                    CountrySegment(chips: [
                        .init(code: "US · CBP", instrument: "7501 · HTSUS", active: true),
                        .init(code: "CA · CBSA", instrument: "B3 · CARM", active: false),
                        .init(code: "MX · SAT", instrument: "PEDIMENTO A1", active: false)])
                    valueHero
                    Text("DECLARATION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    fieldCard(declarationFields)
                    Text("VALUATION + BROKER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    fieldCard(valuationFields)
                    if fileDone {
                        Text("Entry filed with CBP · filed date saved by EusoTrip.").font(EType.caption).foregroundStyle(Brand.success)
                    }
                    if !canFile {
                        Text((entry?.status ?? "draft").lowercased() == "draft"
                             ? "Filing is disabled until every declaration field is live (value · HTS · origin · rate · shipment)."
                             : "This entry is \(statusLabel) — only a draft can be filed.")
                            .font(EType.caption).foregroundStyle(palette.textTertiary)
                    }
                    TriCountryAuthorityBand(title: "TRI-COUNTRY ENTRY · DUTY + TAX REGIME", regimes: [
                        .init(code: "US", authority: "CBP · 7501 · HTSUS", detail: "2.8% ad val · MPF/HMF · USD", consequence: nil, state: .active),
                        .init(code: "CA", authority: "CBSA · B3 · CARM", detail: "duty + 5% GST · CAD", consequence: nil, state: .standby),
                        .init(code: "MX", authority: "SAT · Pedimento A1", detail: "IGI + 16% IVA + DTA · MXN", consequence: nil, state: .standby)])
                    AeoMutualRecognitionStrip()
                    HStack(spacing: 8) {
                        CTAButton(title: "File entry with CBP", action: { Task { await fileEntry() } }, trailingIcon: "paperplane", isLoading: submitting)
                            .disabled(!canFile)
                            .opacity(canFile ? 1 : 0.45)
                        // No edit form on this screen ⇒ nothing to save; minting new
                        // declarations from display state was the B20 fabrication vector.
                        secondaryButton814(title: "Save draft", enabled: false) {}
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · ENTRY FILING").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("CBP 7501 · HTSUS").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 6) {
                Text("Compliance").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var valueHero: some View {
        RimCard814 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("DECLARED VALUE · entry filings").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(text: statusLabel, kind: statusKind)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(declaredValueLabel).font(.system(size: 30, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("EST. DUTY").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                        Text(estDutyLabel).font(.system(size: 20, weight: .heavy, design: .monospaced)).foregroundStyle(Brand.vessel)
                    }
                }
                Divider().overlay(palette.borderFaint)
                Text(heroSub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func fieldCard(_ fields: [FormField814]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.element.id) { idx, f in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(f.label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        HStack(spacing: 8) {
                            Text(f.value).font(.system(size: 14, weight: .bold, design: f.mono ? .monospaced : .default)).foregroundStyle(palette.textPrimary)
                            if let d = f.detail { Text(d).font(.system(size: 11)).foregroundStyle(palette.textSecondary) }
                        }
                    }
                    Spacer(minLength: 0)
                    if let (t, kind) = f.pill { StatusPill(text: t, kind: kind) }
                    if let tr = f.trailing { Text(tr).font(.system(size: 11)).foregroundStyle(palette.textSecondary) }
                    if f.chevron { Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textTertiary) }
                    if f.editGlyph { Image(systemName: "pencil").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary) }
                }
                .padding(.vertical, 12)
                if idx < fields.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
    }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same outline grammar sibling
    /// 757 ships for its secondary CTA.
    private func secondaryButton814(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled || submitting)
        .opacity((!enabled || submitting) ? 0.45 : 1)
    }

    // MARK: Data — hydrate the newest live DRAFT declaration (B20: live data or empty state)

    private func load() async {
        loading = true; loadError = nil
        struct NoInput814: Encodable {}
        do {
            let rows: [CustomsEntryRow814] = try await EusoTripAPI.shared.query(
                "vesselShipments.getCustomsEntries", input: NoInput814())
            let scoped = shipmentId.map { sid in rows.filter { $0.shipmentId == sid } } ?? rows
            // Prefer the newest draft (rows arrive newest-first); fall back to the
            // newest entry of any status so the operator sees the real filing state.
            entry = scoped.first { ($0.status ?? "").lowercased() == "draft" } ?? scoped.first
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// "File entry with CBP": transition the HYDRATED draft via updateCustomsStatus{filed} :693.
    /// Gated by `canFile` — never creates a declaration, never fires on invented values.
    private func fileEntry() async {
        guard !submitting, canFile, let e = entry else { return }
        submitting = true; loadError = nil; fileDone = false
        do {
            let _: UpdateCustomsStatusResp814 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.updateCustomsStatus",
                input: UpdateCustomsStatusInput814(id: e.id, newStatus: "filed"))
            fileDone = true
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        submitting = false
        await load()
    }

    private func numberFmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
    }
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// Gradient-rim hero card — mirrors the gradient-stroked context cards the
/// registered siblings (757 `RimCard757`, 664 `moveContextCard`) ship. The
/// canonical port's `RimCard` is not a shared app symbol.
private struct RimCard814<Content: View>: View {
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

// MARK: - tRPC input / output shapes (per-file; no module-level EmptyInput)

private struct UpdateCustomsStatusInput814: Encodable {
    let id: Int
    let newStatus: String
}
private struct UpdateCustomsStatusResp814: Decodable { let success: Bool?; let id: Int?; let status: String? }

#Preview("814 · Vessel Customs Entry Filing · Night") { VesselCustomsEntryFilingScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("814 · Vessel Customs Entry Filing · Light") { VesselCustomsEntryFilingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
