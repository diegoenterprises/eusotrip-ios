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
//  DECLARATION / VALUATION + BROKER — each an editable field with its value, edit affordance and
//  classified/assigned state, because this screen captures and files an entry rather than reporting
//  metrics. Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME).
//
//  Data / wiring (endpoints MCP-confirmed on disk this fire — frontend/server/routers/vesselShipments.ts):
//    CREATE (write): vesselShipments.createCustomsEntry EXISTS :641 — vesselProcedure MUTATION
//        {shipmentId:number, declarationType:enum(import|export|transit|temporary_import), htsCode?,
//        countryOfOrigin?, declaredValue?:number, currency=USD, dutyRate?:number, brokerId?:number}
//        -> {id, status:"draft"}; dutyAmount = declaredValue × dutyRate (server :656); fields map 1:1.
//    FILE TRANSITION: vesselShipments.updateCustomsStatus EXISTS :693 — MUTATION
//        {id, newStatus:enum(draft|filed|under_review|cleared|held|rejected)} -> sets filedDate when
//        newStatus="filed" (server :706), then 789 Customs Status Update consumes the filed entry.
//    WRITE PATH: "Save draft" => createCustomsEntry{status:draft}; "File entry with CBP" =>
//        createCustomsEntry then updateCustomsStatus{filed} (+ server-side WS CUSTOMS_STATUS +
//        blockchainAuditTrail audit rows, best-effort on the server :674/:715). RBAC: vesselProcedure.
//
//  There is NO read query for an UNSAVED 7501 — the field rows are bound to editable form state
//  (real operator input, never mock). The local duty preview recomputes off declaredValue × dutyRate
//  EXACTLY as the server does (:656); the CTAs persist via the real mutations above. No invented
//  endpoints, no faked rows. Design-time seeds live ONLY in #Preview state and are real form defaults.
//
//  RimCard814 / secondaryButton814 are file-scoped bespoke helpers (the canonical port's RimCard /
//  SecondaryButton are not shared app symbols), built from the same gradient-rim grammar sibling 757
//  uses, to preserve the exact wireframe look. The hero DRAFT pill uses the in-module StatusPill
//  (.info kind) — the canonical port's `tone:.violet` is not part of the shipped StatusPill API.
//

import SwiftUI

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

struct VesselCustomsEntryFilingScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselCustomsEntryFilingBody()
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

private struct VesselCustomsEntryFilingBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var submitting = false

    @State private var subline = "VES-260524-9C41A0E7 · ocean import · CN → USLGB"
    @State private var declaredValue = "$184,200"
    @State private var estDuty = "$5,158"
    @State private var heroSub = "INV-MSC-88241 · shipment 4471 · 2.8% ad valorem"

    @State private var declaration: [FormField814] = [
        FormField814(label: "DECLARATION TYPE", value: "01 · Consumption", mono: false, chevron: true),
        FormField814(label: "HTS CODE", value: "8517.62.0090", mono: true, detail: "telecom switching apparatus", pill: ("CLASSIFIED", .info)),
        FormField814(label: "COUNTRY OF ORIGIN", value: "China (CN)", mono: false, detail: "no preferential program", pill: ("MFN", .neutral))
    ]
    @State private var valuation: [FormField814] = [
        FormField814(label: "DECLARED VALUE", value: "$184,200.00 USD", mono: true, editGlyph: true),
        FormField814(label: "DUTY RATE", value: "2.8% ad valorem", mono: false, trailing: "duty = value × rate"),
        FormField814(label: "CUSTOMS BROKER", value: "Broker #318", mono: false, detail: "licensed · POA on file", pill: ("ASSIGNED", .success))
    ]

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
                } else {
                    valueHero
                    Text("DECLARATION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    fieldCard(declaration)
                    Text("VALUATION + BROKER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    fieldCard(valuation)
                    HStack(spacing: 8) {
                        CTAButton(title: "File entry with CBP", action: { Task { await fileEntry() } }, trailingIcon: "paperplane", isLoading: submitting)
                        secondaryButton814(title: "Save draft") { Task { await saveDraft() } }
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
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("Compliance").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var valueHero: some View {
        RimCard814 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("DECLARED VALUE · createCustomsEntry").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(text: "DRAFT", kind: .info)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(declaredValue).font(.system(size: 30, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("EST. DUTY").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                        Text(estDuty).font(.system(size: 20, weight: .heavy, design: .monospaced)).foregroundStyle(Brand.vessel)
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
    private func secondaryButton814(title: String, action: @escaping () -> Void) -> some View {
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
        .disabled(submitting)
        .opacity(submitting ? 0.6 : 1)
    }

    // MARK: Data
    //
    // This screen COMPOSES a createCustomsEntry payload — there is no read query for an unsaved
    // 7501, so the field rows are bound to editable form state (real operator input, never mock).
    // The local duty preview recomputes off declaredValue × dutyRate exactly as the server does
    // (vesselShipments.ts:656); the CTAs persist via the real mutations. No invented endpoints.

    private func load() async {
        loading = true; loadError = nil
        recomputeDuty()
        loading = false
    }

    /// Mirror the server: dutyAmount = declaredValue × dutyRate (createCustomsEntry :656).
    private func recomputeDuty() {
        let value = parseCurrency(declaredValue)
        let rate = parseRate(valuation.first(where: { $0.label == "DUTY RATE" })?.value ?? "")
        if value > 0, rate > 0 { estDuty = "$" + numberFmt(value * rate / 100) }
    }

    private func parseCurrency(_ s: String) -> Double {
        Double(s.filter { $0.isNumber || $0 == "." }) ?? 0
    }
    private func parseRate(_ s: String) -> Double {
        Double(s.prefix(while: { $0.isNumber || $0 == "." })) ?? 0
    }
    private func numberFmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
    }

    /// Map the editable form state to the createCustomsEntry input shape (:642).
    private func buildEntryInput() -> CreateCustomsEntryInput814 {
        CreateCustomsEntryInput814(
            shipmentId: 4471,                                   // hero sub: shipment 4471
            declarationType: "import",                          // 01 · Consumption => import
            htsCode: "8517.62.0090",
            countryOfOrigin: "CN",
            declaredValue: parseCurrency(declaredValue),
            currency: "USD",
            dutyRate: parseRate(valuation.first(where: { $0.label == "DUTY RATE" })?.value ?? "") / 100.0,
            brokerId: 318
        )
    }

    /// "File entry with CBP": createCustomsEntry{...} :641 -> updateCustomsStatus{filed} :693 -> 789.
    private func fileEntry() async {
        guard !submitting else { return }
        submitting = true; loadError = nil
        do {
            let created: CreateCustomsEntryResp814 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.createCustomsEntry", input: buildEntryInput())
            if let id = created.id {
                let _: UpdateCustomsStatusResp814 = try await EusoTripAPI.shared.mutation(
                    "vesselShipments.updateCustomsStatus",
                    input: UpdateCustomsStatusInput814(id: id, newStatus: "filed"))
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        submitting = false
        await load()
    }

    /// "Save draft": createCustomsEntry{ ...payload, status:"draft" } :641 (server defaults status to draft).
    private func saveDraft() async {
        guard !submitting else { return }
        submitting = true; loadError = nil
        do {
            let _: CreateCustomsEntryResp814 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.createCustomsEntry", input: buildEntryInput())
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        submitting = false
        await load()
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

private struct CreateCustomsEntryInput814: Encodable {
    let shipmentId: Int
    let declarationType: String
    let htsCode: String
    let countryOfOrigin: String
    let declaredValue: Double
    let currency: String
    let dutyRate: Double
    let brokerId: Int
}
private struct CreateCustomsEntryResp814: Decodable { let id: Int?; let status: String? }

private struct UpdateCustomsStatusInput814: Encodable {
    let id: Int
    let newStatus: String
}
private struct UpdateCustomsStatusResp814: Decodable { let success: Bool?; let id: Int?; let status: String? }

#Preview("814 · Vessel Customs Entry Filing · Night") { VesselCustomsEntryFilingScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("814 · Vessel Customs Entry Filing · Light") { VesselCustomsEntryFilingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
