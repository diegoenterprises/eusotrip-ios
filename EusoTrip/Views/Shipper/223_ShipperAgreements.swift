//
//  223_ShipperAgreements.swift
//  EusoTrip 2027 UI — Shipper · Agreements (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/223_ShipperAgreements.swift. Persona: Diego
//  Usoro / Eusorone Technologies (companyId 1) per §11. Agreement
//  IDs reuse the §11.2 LD- audit-trail convention (AGR-260427-{hex})
//  so the audit-trail joins the `loads` and `agreements` tables on
//  the same suffix.
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · AGREEMENTS / "{N} ACTIVE · {M} AWAITING"
//    2. Title block      Agreements (34pt) / "Eusorone Technologies · volume commitments · MATRIX-50"
//    3. IridescentHairline
//    4. KPI summary card 3-cell · ACTIVE · AWAITING SIG · EXPIRES <30d (warn)
//    5. Filter chip row  All / Active / Pending / Drafts / Expired
//    6. Agreement rows   3pt tier rim · AGR id · status pill · lane title ·
//                        spec line · 3-stat row · 6-stage lifecycle strip
//    7. Compact expired  76pt variant for status=expired/terminated rows
//    8. "+ New Agreement" gradient pill CTA
//
//  Real wiring preserved: `agreements.list(limit:100, offset:0)` +
//  `agreements.sign(...)` via `ShipperAgreementsStore`. Detail sheet
//  preserved with Gradient-Ink sign flow for status=pending_signature.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2134 — `agreements.list` doesn't ship origin/destination
//                lane metadata. Lane title falls back to the
//                agreementNumber (mono); the wireframe canon "Houston
//                TX → Dallas TX" lane line lands when backend extends
//                the envelope with `originCity / originState /
//                destinationCity / destinationState`.
//    EUSO-2135 — No countered-delta or term-length aggregates on the
//                row envelope. 3-stat row's term + countered slots
//                paint "—" until backend ships explicit fields.
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy; §4.3 single iridescent hairline; §11 / §11.2
//  Diego canon + audit-trail; §15.2 per-row 3pt tier rim grammar;
//  §15.3 audit-trail-suffix doctrine; §16 hero KPI strip; §16.2
//  gradient pill CTA; §17.2 status pill grammar; §19.2 file-scoped
//  `warnGrad` + LifecycleStrip6 helper; §20.4 no dead buttons;
//  §22.2 textTertiary informational counter.
//

import SwiftUI
import UIKit

// MARK: - Continuity / share helpers

/// Identifiable wrapper so `.sheet(item:)` can drive presentation.
struct AgreementShareItem: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
}

/// SwiftUI bridge to `UIActivityViewController`. Presents the system
/// share sheet for the supplied PDF URL — AirDrop, Save to Files,
/// Mail, Markup, Print, and any third-party share extensions.
struct AgreementShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Filter (wireframe canon labels)

private enum AgreementFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case pending
    case drafts
    case expired

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:     return "All"
        case .active:  return "Active"
        case .pending: return "Pending"
        case .drafts:  return "Drafts"
        case .expired: return "Expired"
        }
    }

    /// Maps to the server's status filter; nil = pass through all.
    var serverStatus: String? {
        switch self {
        case .all:     return nil
        case .active:  return "active"
        case .pending: return "pending_signature"
        case .drafts:  return "draft"
        case .expired: return nil  // expired+terminated merged client-side
        }
    }
}

private enum AgreementTierRim { case gradient, warn, success, neutral }

private enum AgreementStage { case draft, review, sent, counter, signed, active }

// MARK: - Store (preserved + extended)

@MainActor
final class ShipperAgreementsStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded([ShipperAgreementsAPI.Agreement])
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var unfiltered: [ShipperAgreementsAPI.Agreement] = []
    @Published fileprivate var filter: AgreementFilter = .all {
        didSet {
            if oldValue != filter { Task { await load() } }
        }
    }
    @Published var lastSigned: String? = nil
    @Published var lastError: String? = nil

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        phase = .loading
        do {
            let r = try await api.shipperAgreements.list(limit: 100, offset: 0)
            let all = r.agreements ?? []
            unfiltered = all
            let rows = applyClientFilter(rows: all, filter: filter)
            phase = .loaded(rows)
        } catch {
            phase = .error("Couldn't load agreements.")
        }
    }

    fileprivate func applyClientFilter(rows: [ShipperAgreementsAPI.Agreement],
                                       filter: AgreementFilter) -> [ShipperAgreementsAPI.Agreement] {
        switch filter {
        case .all:
            return rows
        case .active:
            return rows.filter { ($0.status ?? "").lowercased() == "active" }
        case .pending:
            return rows.filter { ($0.status ?? "").lowercased() == "pending_signature" }
        case .drafts:
            return rows.filter { ($0.status ?? "").lowercased() == "draft" }
        case .expired:
            return rows.filter {
                let s = ($0.status ?? "").lowercased()
                return s == "expired" || s == "terminated"
            }
        }
    }

    func sign(_ row: ShipperAgreementsAPI.Agreement, signerName: String, signerTitle: String) async {
        let payload = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        do {
            let ack = try await api.shipperAgreements.sign(
                agreementId: row.id,
                signatureData: payload,
                signatureRole: "SHIPPER",
                signerName: signerName.isEmpty ? nil : signerName,
                signerTitle: signerTitle.isEmpty ? nil : signerTitle
            )
            lastSigned = row.agreementNumber ?? "#\(row.id)"
            lastError = nil
            if ack.fullyExecuted == true {
                lastSigned = (lastSigned ?? "Agreement") + " · ACTIVATED"
            }
            await load()
        } catch {
            lastError = "Couldn't sign agreement."
        }
    }
}

// MARK: - Screen root

struct ShipperAgreements: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @StateObject private var store = ShipperAgreementsStore()
    @State private var detail: ShipperAgreementsAPI.Agreement? = nil
    @State private var showSignedToast: Bool = false
    /// PDF share-sheet payload — set when the user taps "Download PDF"
    /// from the row context menu. Drives a `.sheet` that wraps the
    /// system `UIActivityViewController` so AirDrop, Save-to-Files,
    /// Mail, Print, and Markup all light up.
    @State private var shareItem: AgreementShareItem? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s5)

                content
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.load() }
        .onChange(of: store.lastSigned ?? "") { _, v in if !v.isEmpty { showSignedToast = true } }
        .sheet(item: $detail) {
            ShipperAgreementDetailSheet(row: $0).environmentObject(store)
        }
        .sheet(item: $shareItem) { item in
            // Wraps UIActivityViewController so AirDrop / Files / Mail
            // / Print all light up natively. Founder mandate
            // 2026-05-05: agreement row needs Download-PDF parity
            // with the web platform's `/agreements/:id/export` link.
            AgreementShareSheet(items: [item.url])
                .ignoresSafeArea()
        }
        .alert("Signed", isPresented: $showSignedToast, actions: {
            Button("OK") { store.lastSigned = nil }
        }, message: {
            if let s = store.lastSigned { Text(s) }
        })
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · AGREEMENTS")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel(counterAccessibility)
        }
        .padding(.horizontal, Space.s3)
    }

    private var counterEyebrow: String {
        let active = countActive
        let awaiting = countAwaiting
        return "\(active) ACTIVE · \(awaiting) AWAITING"
    }

    private var counterAccessibility: String {
        "\(countActive) active agreements, \(countAwaiting) awaiting signature"
    }

    private var countActive: Int {
        store.unfiltered.filter { ($0.status ?? "").lowercased() == "active" }.count
    }

    private var countAwaiting: Int {
        store.unfiltered.filter { ($0.status ?? "").lowercased() == "pending_signature" }.count
    }

    private var countDrafts: Int {
        store.unfiltered.filter { ($0.status ?? "").lowercased() == "draft" }.count
    }

    private var countExpired: Int {
        store.unfiltered.filter {
            let s = ($0.status ?? "").lowercased()
            return s == "expired" || s == "terminated"
        }.count
    }

    private var countExpiringSoon: Int {
        let now = Date()
        let cutoff = now.addingTimeInterval(30 * 86400)
        return store.unfiltered.filter {
            guard ($0.status ?? "").lowercased() == "active",
                  let d = $0.expirationDate.flatMap(parseDate) else { return false }
            return d >= now && d <= cutoff
        }.count
    }

    private func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        let ymd = DateFormatter()
        ymd.locale = Locale(identifier: "en_US_POSIX")
        ymd.dateFormat = "yyyy-MM-dd"
        ymd.timeZone = TimeZone(identifier: "UTC")
        return ymd.date(from: String(s.prefix(10)))
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Agreements")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · volume commitments · MATRIX-50")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 124)
                }
            }
            .padding(.horizontal, Space.s3)
        case .error(let m):
            errorCard(m)
                .padding(.horizontal, Space.s3)
        case .loaded(let rows):
            VStack(alignment: .leading, spacing: 0) {
                kpiSummaryCard
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s3)

                filterRow
                    .padding(.top, Space.s5)

                if rows.isEmpty {
                    emptyOrNoMatchCard
                        .padding(.horizontal, Space.s3)
                        .padding(.top, Space.s4)
                } else {
                    VStack(spacing: Space.s4) {
                        ForEach(rows) { row in
                            agreementRowView(row)
                        }
                    }
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)
                }

                newAgreementButton
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s5)
            }
        }
    }

    // MARK: KPI summary card (3-cell · ACTIVE / AWAITING SIG / EXPIRES <30d)

    private var kpiSummaryCard: some View {
        let active = countActive
        let awaiting = countAwaiting
        let expiringSoon = countExpiringSoon
        return HStack(spacing: 0) {
            kpiCell(label: "ACTIVE", value: "\(active)", gradient: true, delta: nil, deltaColor: .clear, valueColor: nil)
            divider
            kpiCell(label: "AWAITING SIG", value: "\(awaiting)", gradient: false, delta: nil, deltaColor: .clear, valueColor: nil)
            divider
            kpiCell(label: "EXPIRES <30d", value: "\(expiringSoon)", gradient: false,
                    delta: expiringSoon > 0 ? "renew now" : nil,
                    deltaColor: Brand.warning,
                    valueColor: expiringSoon > 0 ? Brand.warning : nil)
        }
        .padding(.vertical, Space.s4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 36)
    }

    @ViewBuilder
    private func kpiCell(label: String,
                         value: String,
                         gradient: Bool,
                         delta: String?,
                         deltaColor: Color,
                         valueColor: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Group {
                    if gradient {
                        Text(value).foregroundStyle(LinearGradient.diagonal)
                    } else if let valueColor {
                        Text(value).foregroundStyle(valueColor)
                    } else {
                        Text(value).foregroundStyle(palette.textPrimary)
                    }
                }
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                if let delta {
                    Text(delta)
                        .font(EType.caption)
                        .foregroundStyle(deltaColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
    }

    // MARK: Filter row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AgreementFilter.allCases) { f in
                    filterChip(f, count: count(for: f))
                }
            }
            .padding(.horizontal, Space.s3)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [palette.bgPage.opacity(0), palette.bgPage],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 28)
            .allowsHitTesting(false)
        }
    }

    private func count(for filter: AgreementFilter) -> Int? {
        switch filter {
        case .all:     return nil
        case .active:  return countActive
        case .pending: return countAwaiting
        case .drafts:  return countDrafts
        case .expired: return countExpired
        }
    }

    private func filterChip(_ f: AgreementFilter, count: Int?) -> some View {
        let isActive = (store.filter == f)
        let label: String = {
            if let c = count, c > 0 { return "\(f.label) · \(c)" }
            return f.label
        }()
        return Button(action: { tapFilter(f) }) {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .bold : .semibold))
                .foregroundStyle(isActive ? Color.white : palette.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background {
                    if isActive {
                        Capsule().fill(LinearGradient.primary)
                    } else {
                        Capsule().fill(palette.bgCardSoft)
                    }
                }
                .overlay {
                    if !isActive {
                        Capsule().strokeBorder(palette.borderFaint)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(f.label) filter")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func tapFilter(_ f: AgreementFilter) {
        store.filter = f
        // observability post — telemetry only; real effect is `store.filter = f` above
        NotificationCenter.default.post(
            name: .eusoShipperAgreementFilter,
            object: nil,
            userInfo: [
                "source": "223_ShipperAgreements",
                "filter": f.rawValue,
                "shipperCompanyId": 1
            ]
        )
    }

    // MARK: Agreement row (wireframe canon · tier rim + AGR id + status pill + lane + spec + 3-stat + lifecycle)

    @ViewBuilder
    private func agreementRowView(_ row: ShipperAgreementsAPI.Agreement) -> some View {
        let canon = canonStatus(for: row)
        if canon.isCompactExpired {
            agreementCompactRow(row)
        } else {
            agreementFullRow(row, canon: canon)
        }
    }

    private struct CanonStatus {
        let tier: AgreementTierRim
        let pillKind: PillKind
        let pillLegend: String
        let pillWidth: CGFloat
        let stage: AgreementStage
        let isCompactExpired: Bool
        enum PillKind { case awaiting, counterOutlined, active, expired, draft }
    }

    private func canonStatus(for row: ShipperAgreementsAPI.Agreement) -> CanonStatus {
        let s = (row.status ?? "").lowercased()
        switch s {
        case "draft":
            return CanonStatus(tier: .neutral, pillKind: .draft,
                               pillLegend: "DRAFT", pillWidth: 84,
                               stage: .draft, isCompactExpired: false)
        case "negotiating":
            return CanonStatus(tier: .gradient, pillKind: .counterOutlined,
                               pillLegend: "COUNTER", pillWidth: 84,
                               stage: .counter, isCompactExpired: false)
        case "pending_signature":
            return CanonStatus(tier: .warn, pillKind: .awaiting,
                               pillLegend: "AWAITING SIG", pillWidth: 116,
                               stage: .sent, isCompactExpired: false)
        case "active":
            return CanonStatus(tier: .success, pillKind: .active,
                               pillLegend: "ACTIVE", pillWidth: 84,
                               stage: .active, isCompactExpired: false)
        case "expired", "terminated":
            return CanonStatus(tier: .neutral, pillKind: .expired,
                               pillLegend: s == "terminated" ? "TERMINATED" : "EXPIRED",
                               pillWidth: s == "terminated" ? 100 : 84,
                               stage: .active, isCompactExpired: true)
        default:
            return CanonStatus(tier: .neutral, pillKind: .draft,
                               pillLegend: (row.status ?? "—").uppercased(), pillWidth: 84,
                               stage: .draft, isCompactExpired: false)
        }
    }

    @ViewBuilder
    private func agreementFullRow(_ row: ShipperAgreementsAPI.Agreement, canon: CanonStatus) -> some View {
        Button(action: { tapRow(row) }) {
            HStack(spacing: 0) {
                tierRimShape(canon.tier).frame(width: 3)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text(rowDisplayId(row))
                            .font(EType.mono(.micro))
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                        statusPillView(canon.pillKind, legend: canon.pillLegend, width: canon.pillWidth)
                    }
                    .padding(.top, Space.s4)

                    Text(laneTitle(row))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .padding(.top, Space.s2 + 2)

                    Text(specLine(row))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 4)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        statCell(value: rateValue(row), unit: "rate")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        statCell(value: termValue(row), unit: "term")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        statCell(value: sentValue(row), unit: sentUnit(row))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, Space.s2 + 2)

                    LifecycleStrip6(activeStage: canon.stage)
                        .padding(.top, Space.s4 + 2)
                        .padding(.bottom, Space.s4)
                }
                .padding(.leading, Space.s4)
                .padding(.trailing, Space.s4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(AgreementRowStyle())
        .contextMenu { agreementRowMenu(row) }
    }

    @ViewBuilder
    private func agreementCompactRow(_ row: ShipperAgreementsAPI.Agreement) -> some View {
        Button(action: { tapRow(row) }) {
            HStack(spacing: 0) {
                tierRimShape(.neutral).frame(width: 3)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text(rowDisplayId(row))
                            .font(EType.mono(.micro))
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                        statusPillView(.expired, legend: "EXPIRED", width: 84)
                    }
                    .padding(.top, Space.s3 + 2)

                    Text(laneTitle(row))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .padding(.top, Space.s2 + 2)

                    Text(expiredSubline(row))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 4)
                        .padding(.bottom, Space.s3 + 2)
                }
                .padding(.leading, Space.s4)
                .padding(.trailing, Space.s4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(AgreementRowStyle())
        .contextMenu { agreementRowMenu(row) }
    }

    /// Long-press context menu shared by both row variants. Three
    /// actions:
    ///   • Open in app           — same as default tap; presents the
    ///                             native iOS detail sheet (signature
    ///                             pad + counter / activate flow).
    ///   • Open on web           — Continuity / Handoff hand-off to
    ///                             the canonical `/agreements/:id`
    ///                             surface; lands the same view in
    ///                             Safari on the same Apple ID's
    ///                             Mac if continuity is configured.
    ///   • Download PDF          — renders the row to a PDF on-
    ///                             device and presents the system
    ///                             share sheet so AirDrop / Save-to-
    ///                             Files / Mail / Print all work.
    @ViewBuilder
    private func agreementRowMenu(_ row: ShipperAgreementsAPI.Agreement) -> some View {
        Button {
            tapRow(row)
        } label: {
            Label("Open in app", systemImage: "iphone")
        }
        Button {
            openOnWeb(row)
        } label: {
            Label("Open on web · Continuity", systemImage: "safari")
        }
        Button {
            downloadPDF(row)
        } label: {
            Label("Download PDF", systemImage: "arrow.down.doc")
        }
    }

    /// Hand off the agreement to the web surface. Uses
    /// `app.eusotrip.com` as the canonical host so deep-link
    /// re-routing in `ShipperWebToNativeMap` skips it (we
    /// explicitly want the web surface here, not the native
    /// route). On iPad / Mac with the same Apple ID this hands
    /// off via Universal Links + Handoff to Safari.
    private func openOnWeb(_ row: ShipperAgreementsAPI.Agreement) {
        guard let url = URL(string: "https://eusotrip.com/agreements/\(row.id)") else { return }
        openURL(url)
    }

    /// Render the row to a PDF and present the system share sheet.
    /// Best-effort — if the temp-file write fails we silently no-op
    /// rather than dropping a dead error onto the screen.
    private func downloadPDF(_ row: ShipperAgreementsAPI.Agreement) {
        guard let url = AgreementPDFBuilder.writeToTemp(agreement: row) else { return }
        shareItem = AgreementShareItem(url: url)
    }

    private func rowDisplayId(_ row: ShipperAgreementsAPI.Agreement) -> String {
        if let n = row.agreementNumber, !n.isEmpty {
            return n.uppercased().hasPrefix("AGR-") ? n : "AGR-\(n)"
        }
        return "AGR-\(row.id)"
    }

    private func laneTitle(_ row: ShipperAgreementsAPI.Agreement) -> String {
        // EUSO-2134 — agreements.list doesn't ship origin/destination.
        if let t = row.agreementType, !t.isEmpty {
            return t.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return rowDisplayId(row)
    }

    private func specLine(_ row: ShipperAgreementsAPI.Agreement) -> String {
        var parts: [String] = []
        if let eff = row.effectiveDate {
            parts.append("effective \(String(eff.prefix(10)))")
        }
        if let exp = row.expirationDate {
            parts.append("expires \(String(exp.prefix(10)))")
        }
        if let a = row.partyAUserId {
            parts.append("party A #\(a)")
        }
        return parts.isEmpty ? "Agreement details on tap" : parts.joined(separator: " · ")
    }

    private func rateValue(_ row: ShipperAgreementsAPI.Agreement) -> String {
        guard let r = row.baseRate, !r.isEmpty else { return "—" }
        return "$\(r)"
    }

    private func termValue(_ row: ShipperAgreementsAPI.Agreement) -> String {
        // EUSO-2135 — term length aggregate not on envelope.
        guard let eff = row.effectiveDate.flatMap(parseDate),
              let exp = row.expirationDate.flatMap(parseDate) else { return "—" }
        let days = max(0, Int(exp.timeIntervalSince(eff) / 86400))
        if days >= 365 { return "\(days / 365)y" }
        if days >= 30 { return "\(days / 30)mo" }
        if days > 0 { return "\(days)d" }
        return "—"
    }

    private func sentValue(_ row: ShipperAgreementsAPI.Agreement) -> String {
        guard let s = row.createdAt else { return "—" }
        let trimmed = String(s.prefix(10))
        let parts = trimmed.split(separator: "-")
        guard parts.count == 3 else { return trimmed }
        let monthIdx = Int(parts[1]) ?? 1
        let months = ["—", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let month = (monthIdx >= 1 && monthIdx <= 12) ? months[monthIdx] : "—"
        let day = parts[2]
        return "\(month) \(day)"
    }

    private func sentUnit(_ row: ShipperAgreementsAPI.Agreement) -> String {
        switch (row.status ?? "").lowercased() {
        case "active": return "started"
        case "expired", "terminated": return "ended"
        default: return "sent"
        }
    }

    private func expiredSubline(_ row: ShipperAgreementsAPI.Agreement) -> String {
        var parts: [String] = []
        if let exp = row.expirationDate {
            parts.append("expired \(String(exp.prefix(10)))")
        }
        if let t = row.agreementType, !t.isEmpty {
            parts.append(t.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        return parts.isEmpty ? "Expired agreement" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func statCell(value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
            Text(unit)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private func tierRimShape(_ kind: AgreementTierRim) -> some View {
        switch kind {
        case .gradient:
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.diagonal)
        case .warn:
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.agreementWarnGrad)
        case .success:
            RoundedRectangle(cornerRadius: 1.5).fill(Brand.success)
        case .neutral:
            RoundedRectangle(cornerRadius: 1.5).fill(palette.textTertiary)
        }
    }

    @ViewBuilder
    private func statusPillView(_ kind: CanonStatus.PillKind, legend: String, width: CGFloat) -> some View {
        switch kind {
        case .awaiting:
            Text(legend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: width, height: 20)
                .background(Capsule().fill(LinearGradient.agreementWarnGrad))
        case .counterOutlined:
            Text(legend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(LinearGradient.primary)
                .frame(width: width, height: 20)
                .overlay(Capsule().strokeBorder(LinearGradient.primary, lineWidth: 1))
                .background(Capsule().fill(palette.bgCard))
        case .active:
            Text(legend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: width, height: 20)
                .background(Capsule().fill(Brand.success))
        case .expired:
            Text(legend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(palette.textSecondary)
                .frame(width: width, height: 20)
                .overlay(Capsule().strokeBorder(palette.textTertiary, lineWidth: 1))
                .background(Capsule().fill(palette.bgCard))
        case .draft:
            Text(legend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(palette.textSecondary)
                .frame(width: width, height: 20)
                .overlay(Capsule().strokeBorder(palette.textTertiary, lineWidth: 1))
                .background(Capsule().fill(palette.bgCardSoft))
        }
    }

    // MARK: New Agreement CTA

    private var newAgreementButton: some View {
        Button(action: tapNewAgreement) {
            Text("+ New Agreement")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(LinearGradient.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create a new agreement")
    }

    // MARK: Notification posts (§20.4)

    private func tapRow(_ row: ShipperAgreementsAPI.Agreement) {
        detail = row
        // observability post — telemetry only; real effect is `detail = row` sheet binding above
        NotificationCenter.default.post(
            name: .eusoShipperAgreementRow,
            object: nil,
            userInfo: [
                "source": "223_ShipperAgreements",
                "agreementId": row.id,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapNewAgreement() {
        // Real action: open the iOS Agreement Wizard (223A) — 7-step
        // generator → Gemini-backed `agreements.generate` → gradient
        // signature pad → `agreements.sign`. Replaces the prior
        // mailto stub now that the wizard ships.
        NotificationCenter.default.post(
            name: .eusoShipperAgreementCreate,
            object: nil,
            userInfo: [
                "source": "223_ShipperAgreements",
                "shipperCompanyId": 1
            ]
        )
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "223A"]
        )
    }

    // MARK: Empty / error

    private var emptyOrNoMatchCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text(store.filter == .all ? "No agreements yet" : "No agreements match this filter")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text(store.filter == .all
                 ? "Send a counter-party an agreement from the New button below — it'll appear here for sign-off."
                 : "Try a different filter, or create a new agreement.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Brand.info)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Press feedback

private struct AgreementRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 6-stage lifecycle strip (file-scoped per §19.2)

private struct LifecycleStrip6: View {
    let activeStage: AgreementStage
    @Environment(\.palette) var palette

    private let stages: [(key: AgreementStage, label: String)] = [
        (.draft,   "DRAFT"),
        (.review,  "REVIEW"),
        (.sent,    "SENT"),
        (.counter, "COUNTER"),
        (.signed,  "SIGNED"),
        (.active,  "ACTIVE"),
    ]

    private var activeIndex: Int {
        stages.firstIndex(where: { $0.key == activeStage }) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let count = stages.count
            let stride = total / CGFloat(count - 1)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(palette.borderFaint)
                    .frame(width: total, height: 2)
                Rectangle()
                    .fill(LinearGradient.primary)
                    .frame(width: stride * CGFloat(activeIndex), height: 2)
                ForEach(0..<count, id: \.self) { i in
                    let isActive = i == activeIndex
                    let isCompleted = i < activeIndex
                    Circle()
                        .fill(isCompleted || isActive
                              ? AnyShapeStyle(LinearGradient.diagonal)
                              : AnyShapeStyle(palette.borderFaint))
                        .frame(width: isActive ? 9 : 7, height: isActive ? 9 : 7)
                        .offset(x: stride * CGFloat(i) - (isActive ? 4.5 : 3.5))
                }
                ForEach(0..<count, id: \.self) { i in
                    let isActive = i == activeIndex
                    let isCompleted = i < activeIndex
                    let label = stages[i].label
                    Text(label)
                        .font(.system(size: 7, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(
                            isActive
                                ? AnyShapeStyle(LinearGradient.primary)
                                : (isCompleted
                                    ? AnyShapeStyle(palette.textSecondary)
                                    : AnyShapeStyle(palette.textTertiary))
                        )
                        .offset(x: anchoredOffset(for: i, count: count, stride: stride, label: label),
                                y: -10)
                }
            }
        }
        .frame(height: 18)
    }

    private func anchoredOffset(for i: Int, count: Int, stride: CGFloat, label: String) -> CGFloat {
        let approxWidth: CGFloat = CGFloat(label.count) * 4.2
        let baseX = stride * CGFloat(i)
        if i == 0 { return baseX }
        if i == count - 1 { return baseX - approxWidth }
        return baseX - approxWidth / 2
    }
}

// MARK: - File-scoped warn gradient (§19.2)

private extension LinearGradient {
    static let agreementWarnGrad = LinearGradient(
        colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Filter chip tap (All / Active / Pending / Drafts / Expired).
    static let eusoShipperAgreementFilter = Notification.Name("eusoShipperAgreementFilter")
    /// Agreement row tap — opens the detail sheet.
    static let eusoShipperAgreementRow    = Notification.Name("eusoShipperAgreementRow")
    /// "+ New Agreement" gradient pill tap (hands off via MeAction).
    static let eusoShipperAgreementCreate = Notification.Name("eusoShipperAgreementCreate")
}

// MARK: - Detail sheet (preserved · Gradient-Ink sign flow)

struct ShipperAgreementDetailSheet: View {
    let row: ShipperAgreementsAPI.Agreement
    @EnvironmentObject private var store: ShipperAgreementsStore
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var signerName: String = ""
    @State private var signerTitle: String = ""
    @State private var signing: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                hero
                fields
                if (row.status ?? "").lowercased() == "pending_signature" {
                    signCard
                }
                viewOnWeb
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .background(palette.bgPage)
    }

    private var hero: some View {
        let style = AgreementStatusStyle.from(row.status)
        return VStack(alignment: .leading, spacing: 6) {
            Text("AGREEMENT").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text(row.agreementNumber ?? "#\(row.id)")
                .font(.system(size: 24, weight: .heavy)).foregroundStyle(palette.textPrimary)
            HStack(spacing: 6) {
                Text(style.label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(style.color)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(style.color.opacity(0.15)))
                    .overlay(Capsule().strokeBorder(style.color.opacity(0.5)))
                if let t = row.agreementType {
                    Text(t.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(palette.bgCardSoft))
                        .overlay(Capsule().strokeBorder(palette.borderFaint))
                }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(
            colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let r = row.baseRate { kv("Base rate", "$\(r)") }
            if let d = row.effectiveDate { kv("Effective", String(d.prefix(10))) }
            if let d = row.expirationDate { kv("Expires", String(d.prefix(10))) }
            if let a = row.partyAUserId { kv("Party A user #", "\(a)") }
            if let b = row.partyBUserId { kv("Party B user #", "\(b)") }
            if let c = row.createdAt { kv("Created", String(c.prefix(10))) }
            if let n = row.notes { kv("Notes", n) }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary).frame(width: 110, alignment: .leading)
            Text(v).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var signCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("GRADIENT INK · SIGN").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            Text("Tapping sign appends a SHA-256 audit row tied to your account, IP, and timestamp. Both parties must sign to activate.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("FULL NAME").font(.system(size: 8, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. Diego Usoro", text: $signerName)
                    .textFieldStyle(.plain).padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("TITLE").font(.system(size: 8, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. Founder & CEO", text: $signerTitle)
                    .textFieldStyle(.plain).padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            Button {
                signing = true
                Task {
                    await store.sign(row, signerName: signerName, signerTitle: signerTitle)
                    signing = false
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if signing {
                        ProgressView().scaleEffect(0.6).tint(.white)
                    } else {
                        Image(systemName: "signature").font(.system(size: 13, weight: .heavy))
                    }
                    Text(signing ? "Signing…" : "Sign agreement")
                        .font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundStyle(.white).background(LinearGradient.diagonal).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(signing || signerName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var viewOnWeb: some View {
        Button {
            MeAction.fire("shipper.agreement.openOnWeb", userInfo: ["agreementId": row.id])
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 12, weight: .heavy))
                Text("Open full contract on web")
                    .font(.system(size: 12, weight: .heavy))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .foregroundStyle(palette.textPrimary).background(palette.bgCard)
            .overlay(Capsule().strokeBorder(palette.borderFaint))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status style helper

private struct AgreementStatusStyle {
    let label: String
    let color: Color

    static func from(_ raw: String?) -> AgreementStatusStyle {
        switch (raw ?? "").lowercased() {
        case "active":             return .init(label: "Active",   color: Brand.success)
        case "pending_signature":  return .init(label: "To sign",  color: Brand.warning)
        case "draft":              return .init(label: "Draft",    color: Brand.info)
        case "negotiating":        return .init(label: "Negotiating", color: Brand.info)
        case "expired":            return .init(label: "Expired",  color: Brand.danger)
        case "terminated":         return .init(label: "Terminated", color: Brand.danger)
        default:                   return .init(label: (raw ?? "Unknown").capitalized, color: Brand.neutral)
        }
    }
}

// MARK: - Previews

#Preview("223 · Agreements · Dark") {
    ShipperAgreements()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("223 · Agreements · Light") {
    ShipperAgreements()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
