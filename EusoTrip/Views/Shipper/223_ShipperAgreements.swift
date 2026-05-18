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

    // MARK: — State-transition actions (DRAFT → REVIEW → SENT → COUNTER)

    /// Move a draft into pending_review.
    func sendForReview(_ row: ShipperAgreementsAPI.Agreement) async {
        do {
            _ = try await api.shipperAgreements.sendForReview(agreementId: row.id)
            lastSigned = (row.agreementNumber ?? "#\(row.id)") + " · SENT FOR REVIEW"
            lastError = nil
            await load()
        } catch {
            lastError = "Couldn't send for review."
        }
    }

    /// Move a draft / pending_review row into pending_signature.
    func sendForSignature(_ row: ShipperAgreementsAPI.Agreement) async {
        do {
            _ = try await api.shipperAgreements.sendForSignature(agreementId: row.id)
            lastSigned = (row.agreementNumber ?? "#\(row.id)") + " · SENT FOR SIGNATURE"
            lastError = nil
            await load()
        } catch {
            lastError = "Couldn't send for signature."
        }
    }

    /// Push back on terms before signing.
    func counterPropose(
        _ row: ShipperAgreementsAPI.Agreement,
        message: String,
        baseRate: Double?,
        paymentTermDays: Int?,
        notes: String?
    ) async -> Bool {
        do {
            _ = try await api.shipperAgreements.counterPropose(
                agreementId: row.id,
                title: "Counter-proposal",
                message: message.isEmpty ? nil : message,
                proposedBaseRate: baseRate,
                proposedPaymentTermDays: paymentTermDays,
                proposedNotes: notes?.isEmpty == true ? nil : notes
            )
            lastSigned = (row.agreementNumber ?? "#\(row.id)") + " · COUNTER PROPOSED"
            lastError = nil
            await load()
            return true
        } catch let err {
            let msg = (err as NSError).localizedDescription
            lastError = msg.contains("at least one") ? "Set at least one term to counter." : "Couldn't send counter-proposal."
            return false
        }
    }

    /// Accept or reject the most recent counter-proposal.
    func respondToCounter(amendmentId: Int, accept: Bool, on row: ShipperAgreementsAPI.Agreement) async {
        do {
            _ = try await api.shipperAgreements.respondToCounter(
                amendmentId: amendmentId,
                action: accept ? "accept" : "reject"
            )
            lastSigned = (row.agreementNumber ?? "#\(row.id)") + (accept ? " · COUNTER ACCEPTED" : " · COUNTER REJECTED")
            lastError = nil
            await load()
        } catch {
            lastError = "Couldn't respond to counter."
        }
    }

    func amendments(for agreementId: Int) async -> [ShipperAgreementsAPI.Amendment] {
        do { return try await api.shipperAgreements.listAmendments(agreementId: agreementId) }
        catch { return [] }
    }
}

// MARK: - Screen root

struct ShipperAgreements: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @StateObject private var store = ShipperAgreementsStore()
    @EnvironmentObject private var session: EusoTripSession
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
            ShipperAgreementDetailSheet(row: $0)
                .environmentObject(store)
                .environmentObject(session)
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

    /// Long-press context menu shared by both row variants. Two
    /// actions:
    ///   • Open in app           — same as default tap; presents the
    ///                             native iOS detail sheet (signature
    ///                             pad + counter / activate flow).
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
            downloadPDF(row)
        } label: {
            Label("Download PDF", systemImage: "arrow.down.doc")
        }
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

    @State private var sendingForReview: Bool = false
    @State private var sendingForSignature: Bool = false
    @State private var showCounterForm: Bool = false
    @State private var amendments: [ShipperAgreementsAPI.Amendment] = []
    @State private var respondingAmendmentId: Int? = nil

    @EnvironmentObject private var session: EusoTripSession

    private var statusLower: String { (row.status ?? "").lowercased() }
    private var openCounter: ShipperAgreementsAPI.Amendment? {
        amendments.first(where: { ($0.status ?? "") == "proposed" && ($0.title ?? "").hasPrefix("[COUNTER]") })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                hero
                fields
                actionRail
                if let c = openCounter { counterCard(c) }
                if statusLower == "pending_signature" {
                    signCard
                }
                viewOnWeb
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .background(palette.bgPage)
        .task { amendments = await store.amendments(for: row.id) }
        .sheet(isPresented: $showCounterForm) {
            ShipperAgreementCounterForm(row: row) { didSend in
                showCounterForm = false
                if didSend {
                    Task {
                        amendments = await store.amendments(for: row.id)
                        dismiss()
                    }
                }
            }
            .environmentObject(store)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
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

    // MARK: — State-aware action rail
    //
    // The rail's contents depend on the agreement's current status:
    //
    //   draft             → "Send for review", "Send for signature"
    //   pending_review    → "Send for signature", "Counter terms"
    //   pending_signature → "Counter terms" (the sign card lives below)
    //   negotiating       → counter card with Accept / Reject (other party)
    //                       or "Awaiting response" (proposer)
    //   active / expired / terminated → no rail (read-only)

    @ViewBuilder
    private var actionRail: some View {
        switch statusLower {
        case "draft":
            railCard(label: "WORKFLOW") {
                VStack(spacing: 8) {
                    primaryButton(title: sendingForReview ? "Sending…" : "Send for review",
                                  systemImage: "paperplane.fill",
                                  loading: sendingForReview,
                                  disabled: sendingForReview || sendingForSignature) {
                        sendingForReview = true
                        Task {
                            await store.sendForReview(row)
                            sendingForReview = false
                            dismiss()
                        }
                    }
                    primaryButton(title: sendingForSignature ? "Sending…" : "Skip review · Send for signature",
                                  systemImage: "signature",
                                  variant: .outline,
                                  loading: sendingForSignature,
                                  disabled: sendingForReview || sendingForSignature) {
                        sendingForSignature = true
                        Task {
                            await store.sendForSignature(row)
                            sendingForSignature = false
                            dismiss()
                        }
                    }
                }
            }
        case "pending_review":
            railCard(label: "REVIEW") {
                VStack(spacing: 8) {
                    primaryButton(title: sendingForSignature ? "Sending…" : "Send for signature",
                                  systemImage: "paperplane.fill",
                                  loading: sendingForSignature,
                                  disabled: sendingForSignature) {
                        sendingForSignature = true
                        Task {
                            await store.sendForSignature(row)
                            sendingForSignature = false
                            dismiss()
                        }
                    }
                    primaryButton(title: "Counter terms",
                                  systemImage: "arrow.uturn.backward.circle",
                                  variant: .outline) {
                        showCounterForm = true
                    }
                }
            }
        case "pending_signature":
            railCard(label: "DECISION") {
                primaryButton(title: "Counter terms instead of signing",
                              systemImage: "arrow.uturn.backward.circle",
                              variant: .outline) {
                    showCounterForm = true
                }
            }
        case "negotiating":
            // Rail content lives in `counterCard(_:)` directly so the
            // proposed deltas render alongside the action buttons.
            EmptyView()
        default:
            EmptyView()
        }
    }

    private func counterCard(_ a: ShipperAgreementsAPI.Amendment) -> some View {
        // Display the open counter-proposal. The party who DIDN'T
        // propose sees Accept / Reject; the proposer sees an
        // "Awaiting response" affordance.
        let mine = currentUserIsProposer(a)
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text("COUNTER-PROPOSAL · #\(a.amendmentNumber ?? 0)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
            }
            if let d = a.description, !d.isEmpty {
                Text(d).font(EType.body).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach((a.changes ?? []), id: \.field) { c in
                    HStack(alignment: .firstTextBaseline) {
                        Text(humanField(c.field))
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .frame(width: 110, alignment: .leading)
                        Text(c.oldDisplay)
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .strikethrough()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                        Text(c.newDisplay)
                            .font(EType.bodyStrong).foregroundStyle(Brand.warning)
                        Spacer(minLength: 0)
                    }
                }
            }
            if mine {
                Text("Waiting on the other party to accept or reject your counter.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                HStack(spacing: 8) {
                    Button {
                        respondingAmendmentId = a.id
                        Task {
                            await store.respondToCounter(amendmentId: a.id, accept: true, on: row)
                            respondingAmendmentId = nil
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if respondingAmendmentId == a.id {
                                ProgressView().scaleEffect(0.6).tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .heavy))
                            }
                            Text("Accept counter")
                                .font(.system(size: 13, weight: .heavy))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(respondingAmendmentId != nil)

                    Button {
                        respondingAmendmentId = a.id
                        Task {
                            await store.respondToCounter(amendmentId: a.id, accept: false, on: row)
                            respondingAmendmentId = nil
                            dismiss()
                        }
                    } label: {
                        Text("Reject")
                            .font(.system(size: 13, weight: .heavy))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(palette.textPrimary)
                            .background(palette.bgCardSoft)
                            .overlay(Capsule().strokeBorder(palette.borderFaint))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(respondingAmendmentId != nil)
                }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func currentUserIsProposer(_ a: ShipperAgreementsAPI.Amendment) -> Bool {
        // Compare the proposer userId from the amendment against the
        // signed-in session user. The server still enforces "the
        // proposer cannot respond to their own counter" — this check
        // only controls which copy / buttons the UI shows.
        guard let proposedBy = a.proposedBy,
              let me = session.user?.id,
              let meInt = Int(me) else { return false }
        return proposedBy == meInt
    }

    private func humanField(_ raw: String) -> String {
        switch raw {
        case "baseRate": return "BASE RATE"
        case "paymentTermDays": return "NET DAYS"
        case "effectiveDate": return "EFFECTIVE"
        case "expirationDate": return "EXPIRES"
        case "notes": return "NOTES"
        default: return raw.uppercased()
        }
    }

    // MARK: — Rail primitives

    private enum ButtonVariant { case filled, outline }

    @ViewBuilder
    private func primaryButton(title: String, systemImage: String,
                               variant: ButtonVariant = .filled,
                               loading: Bool = false,
                               disabled: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading {
                    ProgressView().scaleEffect(0.6).tint(variant == .filled ? .white : palette.textPrimary)
                } else {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .heavy))
                }
                Text(title).font(.system(size: 14, weight: .heavy))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .foregroundStyle(variant == .filled ? .white : palette.textPrimary)
            .background(variant == .filled ? AnyView(LinearGradient.diagonal) : AnyView(palette.bgCardSoft))
            .overlay(variant == .outline
                     ? AnyView(Capsule().strokeBorder(palette.borderFaint))
                     : AnyView(EmptyView()))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1.0)
    }

    @ViewBuilder
    private func railCard<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            content()
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
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

    @State private var presentingPDFViewer: Bool = false

    /// Renders the contract IN-APP via EusoPDFViewer with gradient-
    /// ink signing capabilities. Replaces the prior "Open full
    /// contract on web" hand-off per founder doctrine 2026-05-07
    /// — every contract is viewed in our own canvas, signed with
    /// our brand ink, never punted to the browser.
    private var viewOnWeb: some View {
        Button {
            presentingPDFViewer = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 12, weight: .heavy))
                Text("Open full contract")
                    .font(.system(size: 12, weight: .heavy))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .padding(.horizontal, 14)
            .foregroundStyle(.white)
            .background(LinearGradient.diagonal)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presentingPDFViewer) {
            // Build the contract PDF URL from the agreement record.
            // Server endpoint: agreements.getPDFURL(agreementId).
            // When the URL isn't populated yet, the viewer's load
            // path surfaces an honest empty state — never a fake
            // PDF.
            let pdfURL = URL(string: "https://eusotrip.com/api/agreements/\(row.id)/pdf")
            EusoPDFViewer(
                title: row.agreementNumber ?? "Agreement #\(row.id)",
                subtitle: (row.agreementType ?? "Contract") + (row.status.map { " · \($0.uppercased())" } ?? ""),
                source: .url(pdfURL ?? URL(string: "about:blank")!),
                allowSigning: (row.status ?? "").lowercased() == "pending_signature",
                onSigned: { _, base64 in
                    Task {
                        // Submit gradient-ink signature back to the
                        // agreement record. Best-effort — the
                        // mutation is server-routed; a failure
                        // surfaces in the next refresh.
                        struct In: Encodable {
                            let agreementId: Int
                            let signatureBase64: String
                            let signedAt: String
                        }
                        struct Out: Decodable { let success: Bool? }
                        let iso = ISO8601DateFormatter().string(from: Date())
                        let _: Out? = try? await EusoTripAPI.shared.mutation(
                            "agreements.submitSignature",
                            input: In(
                                agreementId: row.id,
                                signatureBase64: base64,
                                signedAt: iso
                            )
                        )
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Status style helper

private struct AgreementStatusStyle {
    let label: String
    let color: Color

    static func from(_ raw: String?) -> AgreementStatusStyle {
        switch (raw ?? "").lowercased() {
        case "active":             return .init(label: "Active",   color: Brand.success)
        case "pending_review":     return .init(label: "Review",   color: Brand.info)
        case "pending_signature":  return .init(label: "To sign",  color: Brand.warning)
        case "draft":              return .init(label: "Draft",    color: Brand.info)
        case "negotiating":        return .init(label: "Counter open", color: Brand.warning)
        case "expired":            return .init(label: "Expired",  color: Brand.danger)
        case "terminated":         return .init(label: "Terminated", color: Brand.danger)
        default:                   return .init(label: (raw ?? "Unknown").capitalized, color: Brand.neutral)
        }
    }
}

// MARK: - Counter-proposal form
//
// Surface the negotiable terms (base rate, payment net days, notes) so
// the receiving party can push back on the agreement without signing.
// At least one field must be touched — the server enforces this too.

struct ShipperAgreementCounterForm: View {
    let row: ShipperAgreementsAPI.Agreement
    let onClose: (_ didSend: Bool) -> Void

    @EnvironmentObject private var store: ShipperAgreementsStore
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var message: String = ""
    @State private var baseRateText: String = ""
    @State private var paymentTermDaysText: String = ""
    @State private var notes: String = ""
    @State private var sending: Bool = false
    @State private var formError: String? = nil

    private var trimmedRate: Double? {
        let s = baseRateText.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        return s.isEmpty ? nil : Double(s)
    }
    private var trimmedDays: Int? {
        let s = paymentTermDaysText.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : Int(s)
    }
    private var hasAtLeastOneChange: Bool {
        trimmedRate != nil
            || trimmedDays != nil
            || !notes.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                messageBlock
                termsBlock
                if let e = formError {
                    Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                        .padding(.horizontal, 14)
                }
                sendButton
                Color.clear.frame(height: 60)
            }
            .padding(.top, 12)
        }
        .background(palette.bgPage)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COUNTER-PROPOSAL").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text(row.agreementNumber ?? "#\(row.id)")
                .font(.system(size: 24, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Push back on terms before signing. The other party gets notified and can Accept or Reject your counter — both parties re-sign once accepted.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
    }

    private var messageBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MESSAGE (OPTIONAL)").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            TextEditor(text: $message)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(8)
                .background(palette.bgCardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .padding(.horizontal, 14)
    }

    private var termsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROPOSED TERMS").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)

            field(label: "BASE RATE (USD)",
                  placeholder: row.baseRate.map { "Current: $\($0)" } ?? "e.g. 2750.00",
                  text: $baseRateText, keyboard: .decimalPad)

            field(label: "PAYMENT NET DAYS",
                  placeholder: "Current: 30",
                  text: $paymentTermDaysText, keyboard: .numberPad)

            VStack(alignment: .leading, spacing: 6) {
                Text("NOTES / TERMS CHANGE").font(.system(size: 8, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                TextEditor(text: $notes)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60)
                    .padding(8)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
        .padding(.horizontal, 14)
    }

    private func field(label: String, placeholder: String,
                       text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(palette.bgCardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
    }

    private var sendButton: some View {
        Button {
            guard hasAtLeastOneChange else {
                formError = "Set at least one term to counter."
                return
            }
            formError = nil
            sending = true
            Task {
                let ok = await store.counterPropose(
                    row,
                    message: message,
                    baseRate: trimmedRate,
                    paymentTermDays: trimmedDays,
                    notes: notes.isEmpty ? nil : notes
                )
                sending = false
                if ok { onClose(true) } else { formError = store.lastError }
            }
        } label: {
            HStack(spacing: 8) {
                if sending {
                    ProgressView().scaleEffect(0.6).tint(.white)
                } else {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 14, weight: .heavy))
                }
                Text(sending ? "Sending…" : "Send counter-proposal")
                    .font(.system(size: 14, weight: .heavy))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .foregroundStyle(.white).background(LinearGradient.diagonal).clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .disabled(sending || !hasAtLeastOneChange)
        .opacity((sending || !hasAtLeastOneChange) ? 0.6 : 1.0)
    }
}

// MARK: - Previews

#Preview("223 · Agreements · Dark") {
    ShipperAgreements()
        .environment(\.palette, Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("223 · Agreements · Light") {
    ShipperAgreements()
        .environment(\.palette, Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
