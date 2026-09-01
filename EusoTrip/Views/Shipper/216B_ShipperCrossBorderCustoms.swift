//
//  216B_ShipperCrossBorderCustoms.swift
//  EusoTrip 2027 - Shipper cross-border customs gate (drill-down of 216 Compliance).
//
//  ARCHETYPE: COMPLIANCE / GATE. The CLEAR/HOLD verdict and the filing
//  checklist are the server's own clearance derivation for this load: the
//  required-document matrix is built from the load's recorded countries and
//  each row is marked filed only when a matching document row exists. This
//  screen adds no documents of its own and asserts no duty figure.
//
//  SwiftUI twin of:
//    02 Shipper/Light-SVG/216B Shipper Cross-Border Customs.svg
//    02 Shipper/Dark-SVG/216B Shipper Cross-Border Customs.svg
//
//  ── WIRING MANIFEST (line-confirmed on disk frontend/server/routers/) ──
//    loads.getById                        EXISTS · loads.ts:1225
//    shippers.getCrossBorderClearance     EXISTS · shippers.ts:3424
//        input {loadId, direction?} → {cleared, customsStatus, usmcaEligible,
//        laneLabel, crossingEstimate, docs[{name,detail,filed}], missingDocs[]}
//    shippers.getCrossBorderSummary       EXISTS · shippers.ts:3353
//        → {lanes[], trustedPrograms[]}   (the trusted-programs roster)
//    crossBorderShipping.getExchangeRates EXISTS · crossBorder.ts:2681
//        NOTE ON NAMESPACE: routers.ts:3214-3216 mounts crossBorderCompliance.ts
//        at `crossBorder` and crossBorder.ts at `crossBorderShipping`. The
//        wireframe header called this `crossBorder.*`; that path resolves to a
//        DIFFERENT router. The mounted name is used here.
//  NOT CALLED — no such procedure exists tree-wide:
//    crossBorder.filePedimento   MISSING · the SVG's "File pedimento" CTA has
//      no backing mutation, so the screen shows a named unavailable state.
//    crossBorder.getBorderWait   MISSING · live crossing wait is served by
//      216F (crossBorderShipping.recommendCrossings), not by this screen.
//
//  DELIBERATE OMISSIONS (each would have required inventing data):
//    · The SVG's "USMCA DUTY $0.00 · saved" tile is NOT rendered. No procedure
//      returns a duty amount for a load; a green $0.00 would be a fabricated
//      money figure and a fabricated compliance signal at once.
//    · The SVG's fixed crossing name ("World Trade Bridge") is NOT rendered.
//      getCrossBorderClearance returns `crossingEstimate` as null today, so
//      the tile reads honestly as not recorded.
//
//  §W OFFLINE POLICY: ONLINE_ONLY(customs clearance is re-derived from the
//  load's filed documents on every query; a cached CLEAR could authorise a
//  crossing whose paperwork lapsed or was voided since the cache was
//  written). Nothing is persisted client-side.
//
//  — Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Decoded models

private struct CustomsLocation216B: Decodable {
    let city: String?
    let state: String?
}

private struct CustomsLoad216B: Decodable {
    let id: String
    let loadNumber: String
    let status: String
    let commodity: String?
    let commodityName: String?
    let originCountry: String?
    let destCountry: String?
    let pickupLocation: CustomsLocation216B?
    let deliveryLocation: CustomsLocation216B?

    var lane: String {
        "\(location(pickupLocation)) -> \(location(deliveryLocation))"
    }

    private func location(_ value: CustomsLocation216B?) -> String {
        let parts = [value?.city, value?.state]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Location not recorded" : parts.joined(separator: ", ")
    }
}

private struct CustomsFiling216B: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let detail: String?
    let filed: Bool
}

private struct CustomsClearance216B: Decodable {
    let loadId: String
    let direction: String
    let cleared: Bool
    let customsStatus: String
    let usmcaEligible: Bool
    let laneLabel: String?
    let crossingEstimate: String?
    let docs: [CustomsFiling216B]
    let missingDocs: [String]

    var filedCount: Int { docs.filter(\.filed).count }
    var outstanding: [CustomsFiling216B] { docs.filter { !$0.filed } }
}

private struct CustomsSummary216B: Decodable {
    let trustedPrograms: [String]
}

/// A corridor regulator row. Statutory bodies for the recorded countries —
/// declared as a named type (not a tuple) so `ForEach` has a real identity.
private struct CorridorAuthority216B: Identifiable {
    let id: String
    let title: String
    let detail: String
}

private struct CustomsExchangeRates216B: Decodable {
    struct Rates: Decodable {
        let USD: Double?
        let CAD: Double?
        let MXN: Double?
    }

    let base: String
    let rates: Rates
    let updatedAt: String?
    let source: String

    /// Matches the trust gate 216G already ships: a fallback table is never
    /// presented as a current financial quote.
    var isTrustedForDisplay: Bool {
        source == "live" || source == "cached"
    }
}

// MARK: - Store

@MainActor
private final class CrossBorderCustomsStore216B: ObservableObject {
    @Published private(set) var load: CustomsLoad216B?
    @Published private(set) var clearance: CustomsClearance216B?
    @Published private(set) var trustedPrograms: [String] = []
    @Published private(set) var exchangeRates: CustomsExchangeRates216B?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    let loadId: String
    private let api: EusoTripAPI

    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    private func clear() {
        load = nil
        clearance = nil
        trustedPrograms = []
        exchangeRates = nil
    }

    func refresh() async {
        guard !loadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clear()
            errorMessage = "Open the customs gate from a cross-border load to see its filings."
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            struct LoadInput: Encodable { let id: String }
            let result: CustomsLoad216B? = try await api.query(
                "loads.getById",
                input: LoadInput(id: loadId)
            )
            guard let resolved = result else {
                clear()
                errorMessage = "This load is no longer available. Return to Loads and choose another one."
                return
            }
            load = resolved

            var failures: [String] = []

            struct ClearanceInput: Encodable {
                let loadId: String
                let direction: String?
            }
            do {
                clearance = try await api.query(
                    "shippers.getCrossBorderClearance",
                    input: ClearanceInput(loadId: loadId, direction: nil)
                )
            } catch {
                clearance = nil
                failures.append(error.eusoUserCopy)
            }

            do {
                let summary: CustomsSummary216B = try await api.queryNoInput(
                    "shippers.getCrossBorderSummary"
                )
                trustedPrograms = summary.trustedPrograms
            } catch {
                trustedPrograms = []
                failures.append(error.eusoUserCopy)
            }

            struct ExchangeInput: Encodable { let base: String }
            do {
                exchangeRates = try await api.query(
                    "crossBorderShipping.getExchangeRates",
                    input: ExchangeInput(base: "USD")
                )
            } catch {
                exchangeRates = nil
                failures.append(error.eusoUserCopy)
            }

            errorMessage = failures.isEmpty ? nil : failures.joined(separator: " ")
        } catch {
            clear()
            errorMessage = error.eusoUserCopy
        }
    }
}

// MARK: - Screen

struct ShipperCrossBorderCustoms: View {
    let loadId: String
    @StateObject private var store: CrossBorderCustomsStore216B
    @Environment(\.palette) private var palette

    init(loadId: String = "") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: CrossBorderCustomsStore216B(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(
                    eyebrow: eyebrow,
                    idText: store.load?.loadNumber ?? loadId,
                    title: "Customs gate"
                )

                if let errorMessage = store.errorMessage {
                    DegradedNote(text: errorMessage)
                        .padding(.top, Space.s3)
                }

                if store.isLoading, store.load == nil {
                    ProgressView("Loading clearance record")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s6)
                }

                if let load = store.load {
                    loadCard(load)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)

                    if let clearance = store.clearance {
                        SectionLabel("CLEARANCE VERDICT")
                            .padding(.top, Space.s5)
                        verdictCard(clearance)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)

                        SectionLabel("CUSTOMS FILINGS · \(clearance.docs.count)")
                            .padding(.top, Space.s5)
                        filingList(clearance)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)

                        SectionLabel("CROSSING FACTS")
                            .padding(.top, Space.s5)
                        factsStrip(clearance)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)
                    }

                    SectionLabel("TRUSTED PROGRAMS")
                        .padding(.top, Space.s5)
                    trustedProgramsCard
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    SectionLabel("CORRIDOR AUTHORITIES")
                        .padding(.top, Space.s5)
                    corridorCard(load)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    SectionLabel("RELATED FOR THIS LOAD")
                        .padding(.top, Space.s5)
                    relatedCard
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    filingGapNote
                        .padding(.top, Space.s5)
                }

                if !loadId.isEmpty {
                    AddendaCTAPair(
                        primary: "Refresh clearance",
                        secondary: "Message ESang",
                        primaryLoading: store.isLoading,
                        onPrimary: { Task { await store.refresh() } }
                    )
                    .padding(.top, Space.s5)
                }

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .eusoRefreshable { await store.refresh() }
    }

    private var eyebrow: String {
        if let direction = store.clearance?.direction, !direction.isEmpty {
            return "SHIPPER · CROSS-BORDER · \(direction.uppercased())"
        }
        return "SHIPPER · CROSS-BORDER · CUSTOMS"
    }

    // MARK: Load identity

    private func loadCard(_ load: CustomsLoad216B) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                AddendaIconChip(systemImage: "globe.americas.fill", tint: Brand.info)
                VStack(alignment: .leading, spacing: 4) {
                    Text(load.commodityName ?? load.commodity ?? "Cargo not recorded")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text(store.clearance?.laneLabel ?? load.lane)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                AddendaChip(
                    text: load.status.replacingOccurrences(of: "_", with: " ").uppercased(),
                    color: Brand.info
                )
            }
            Divider().overlay(palette.borderFaint)
            factRow("COUNTRIES", countryLane(load))
            if let clearance = store.clearance {
                factRow("CUSTOMS STATUS", clearance.customsStatus.replacingOccurrences(of: "_", with: " ").uppercased())
                factRow("USMCA GEOGRAPHY", clearance.usmcaEligible ? "US / CA / MX lane" : "Outside USMCA")
            }
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    // MARK: Verdict

    private func verdictCard(_ clearance: CustomsClearance216B) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                AddendaIconChip(
                    systemImage: clearance.cleared ? "checkmark.seal.fill" : "hand.raised.fill",
                    tint: clearance.cleared ? Brand.success : Brand.danger
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(clearance.cleared ? "CLEAR" : "HOLD")
                        .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                        .foregroundStyle(clearance.cleared ? Brand.success : Brand.danger)
                    Text(verdictSubtitle(clearance))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            gateBar(clearance)
            Text("Cleared means every required filing this lane needs has a matching document on the load and the load is not on hold. It is not a customs release, a broker approval, or a border authority decision.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private func verdictSubtitle(_ clearance: CustomsClearance216B) -> String {
        if clearance.docs.isEmpty {
            return "No required-filing matrix was produced for this lane."
        }
        let outstanding = clearance.outstanding.count
        if outstanding == 0 {
            return "\(clearance.filedCount) of \(clearance.docs.count) filings on file."
        }
        return "\(outstanding) filing\(outstanding == 1 ? "" : "s") outstanding · \(clearance.filedCount) of \(clearance.docs.count) on file"
    }

    private func gateBar(_ clearance: CustomsClearance216B) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(clearance.docs) { doc in
                    Capsule()
                        .fill(doc.filed ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(Brand.danger.opacity(0.30)))
                        .frame(height: 8)
                }
            }
            if let firstFiled = clearance.docs.first(where: \.filed)?.name,
               let firstOutstanding = clearance.outstanding.first?.name {
                HStack {
                    Text(firstFiled.uppercased())
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: Space.s2)
                    Text("\(firstOutstanding.uppercased()) DUE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.danger)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: Filings

    private func filingList(_ clearance: CustomsClearance216B) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if clearance.docs.isEmpty {
                Text("The server produced no required-filing matrix for this load. That happens when the load's origin or destination country is not recorded, or when the load is not visible to this account.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.s4)
            } else {
                ForEach(Array(clearance.docs.enumerated()), id: \.element.id) { index, doc in
                    filingRow(doc)
                    if index < clearance.docs.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.leading, 56)
                    }
                }
            }
        }
        .addendaPanel(palette)
    }

    private func filingRow(_ doc: CustomsFiling216B) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            AddendaIconChip(
                systemImage: doc.filed ? "checkmark.circle.fill" : "doc.badge.ellipsis",
                tint: doc.filed ? Brand.success : Brand.danger
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(doc.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.s2)
                    AddendaChip(
                        text: doc.filed ? "FILED" : "NEEDED",
                        color: doc.filed ? Brand.success : Brand.danger
                    )
                }
                if let detail = doc.detail, !detail.isEmpty {
                    Text(detail)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
    }

    // MARK: Facts

    private func factsStrip(_ clearance: CustomsClearance216B) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            factRow("CROSSING", clearance.crossingEstimate?.isEmpty == false
                    ? clearance.crossingEstimate!
                    : "Not recorded on this load")
            Divider().overlay(palette.borderFaint)
            if let rates = store.exchangeRates,
               rates.isTrustedForDisplay,
               let mxn = rates.rates.MXN {
                factRow("FX · MXN PER \(rates.base)", String(format: "%.4f", mxn))
                factRow("FX SOURCE", "\(rates.source.uppercased())\(updatedSuffix(rates.updatedAt))")
            } else {
                factRow("FX · MXN", "Trusted rate unavailable")
                Text("A fallback exchange table is intentionally not shown as a current rate, and no duty or converted value is computed from one.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(palette.borderFaint)
            Text("EusoTrip does not compute a duty amount for this load. USMCA preferential treatment is a claim made on the certificate of origin, evaluated on the USMCA origin screen — not a figure this gate can assert.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    // MARK: Trusted programs

    @ViewBuilder
    private var trustedProgramsCard: some View {
        if store.trustedPrograms.isEmpty {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "person.badge.shield.checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No trusted-trader programs derived")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text("The roster is derived from this account's recorded cross-border lanes. With no such lanes on file, no program is claimed.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .addendaPanel(palette)
        } else {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    ForEach(store.trustedPrograms, id: \.self) { program in
                        AddendaChip(text: program.uppercased(), color: Brand.info)
                    }
                    Spacer(minLength: 0)
                }
                Text("Derived from the cross-border lanes recorded for this account. Program eligibility is a lane-geography derivation, not proof of an active certification.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s4)
            .addendaPanel(palette)
        }
    }

    // MARK: Corridor authorities

    /// Regulator names for the recorded corridor. These are statutory bodies,
    /// not load data — labelled as such so nothing here reads as a record.
    private func corridorCard(_ load: CustomsLoad216B) -> some View {
        let rows = corridorAuthorities(load)
        return VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text("Origin and destination countries are not recorded on this load, so no corridor authority can be named.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.s4)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                        Spacer(minLength: Space.s3)
                        Text(row.detail)
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(Space.s4)
                    if index < rows.count - 1 {
                        Divider().overlay(palette.borderFaint)
                    }
                }
            }
        }
        .addendaPanel(palette)
    }

    private func corridorAuthorities(_ load: CustomsLoad216B) -> [CorridorAuthority216B] {
        let countries = Set(
            [load.originCountry, load.destCountry]
                .compactMap { $0?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let catalog: [CorridorAuthority216B] = [
            CorridorAuthority216B(id: "US", title: "US · CBP", detail: "ACE eManifest · C-TPAT"),
            CorridorAuthority216B(id: "CA", title: "CA · CBSA", detail: "ACI · PIP"),
            CorridorAuthority216B(id: "MX", title: "MX · SAT", detail: "VUCEM · NEEC · Carta Porte"),
        ]
        return catalog.filter { countries.contains($0.id) }
    }

    // MARK: Related drill-downs (§27 inbound edges · 216B → 216D / 216F)

    /// Onward navigation for the same load. The load id travels in the
    /// notification payload exactly the way 205 and 261 carry theirs, so
    /// the destination mounts on a real record rather than its empty state.
    private var relatedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            relatedRow(
                screenId: "216D",
                title: "USMCA origin",
                subtitle: "Preferential-origin rules check for this load",
                systemImage: "checkmark.seal"
            )
            Divider().overlay(palette.borderFaint).padding(.leading, 56)
            relatedRow(
                screenId: "216F",
                title: "Border wait",
                subtitle: "Ranked crossings from this load's pickup anchor",
                systemImage: "road.lanes"
            )
        }
        .addendaPanel(palette)
    }

    private func relatedRow(
        screenId: String,
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap,
                object: nil,
                userInfo: ["screenId": screenId, "loadId": loadId]
            )
        } label: {
            HStack(alignment: .center, spacing: Space.s3) {
                AddendaIconChip(systemImage: systemImage, tint: Brand.info, side: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(loadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    // MARK: Named backend gap

    private var filingGapNote: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            SectionLabel("FILING FROM THIS SCREEN")
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Filing a pedimento here is unavailable")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text("Submitting a VUCEM pedimento from this screen would need a mutation that does not exist on the server (crossBorder.filePedimento is not implemented). Outstanding filings must be uploaded through the load's document flow; this gate re-derives on the next refresh.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .addendaPanel(palette)
            .padding(.horizontal, Space.s5)
        }
    }

    // MARK: Shared parts

    private func updatedSuffix(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return " · updated \(value)"
    }

    private func countryLane(_ load: CustomsLoad216B) -> String {
        "\(load.originCountry?.uppercased() ?? "Not recorded") -> \(load.destCountry?.uppercased() ?? "Not recorded")"
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s3)
            Text(value)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview("216B · Cross-Border Customs · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperCrossBorderCustoms()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("216B · Cross-Border Customs · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperCrossBorderCustoms()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
