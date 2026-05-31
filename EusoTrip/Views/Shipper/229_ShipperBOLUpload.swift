//
//  229_ShipperBOLUpload.swift
//  EusoTrip 2027 UI — Shipper · BOL Upload (de-fabricated 2026-05-31)
//
//  DE-FABRICATION 2026-05-31 — this surface previously rendered a
//  fully hardcoded BOL (Houston→Dallas tanker, fixed BOL id, three
//  canned §11 signatory rows) with NO network fetch despite a header
//  claiming `documents.getAll`. FOUNDER BAR: zero fake/seed business
//  data. The hero card + KPI quartet now render LIVE rows from
//  `documents.getAll` filtered to the BOL category (mirrors
//  300_DocumentsAll's proc-call + state pattern). Where no live source
//  exists, the field shows an honest em-dash "—"; where no endpoint
//  exists at all (the per-party signatory state), the section shows an
//  honest empty state — never fabricated rows.
//
//  Layout (top → bottom), bespoke UI unchanged:
//    1. TopBar           ✦ SHIPPER · BOL UPLOAD / live "N BOL" counter
//    2. Back chevron + breadcrumb "Loads"
//    3. Title block      32pt "BOL detail" + sub line from live doc
//    4. IridescentHairline
//    5. Hero BOL card    3pt rim + live BOL id + live status pill +
//                        live name + uploaded-at + lifecycle strip
//                        driven by live status
//    6. KPI quartet      4-cell · PAGES · SIZE · INTEGRITY · SIGNED
//                        (SIZE live; the rest honest em-dash w/ gap ref)
//    7. SIGNATORIES      honest empty state — no signatory endpoint
//    8. View audit trail gradient mid-link
//
//  Real wiring: `documents.getAll(category:"BOL")` via DocumentsAPI.
//  When a `loadId` is supplied we surface the BOL whose name carries
//  that anchor; otherwise the most-recent BOL row. Empty + error +
//  loading states all mirror the sibling live screen.
//
//  Backend gaps surfaced HONESTLY (no fake data fills them):
//    EUSO-2147 — `documents.bol.getDetail(loadId:)` not yet on iOS
//                API. Lane / spec / page-count / SHA-256 integrity are
//                NOT in the `documents.getAll` projection, so they
//                render "—" until that envelope ships.
//    EUSO-2148 — `documents.bol.getSignatories(bolId:)` not shipped.
//                The SIGNATORIES section renders an honest empty state
//                (was three fabricated persona rows) until it lands.
//
//  Doctrine refs: §2 LOADS-tab nav; §3 numbers-first copy; §4.3 single
//  iridescent hairline; §15.3 audit-trail BOL-{hex} suffix; §17.2 KPI
//  quartet recipe; §19.2 file-scoped LifecycleStrip4BOL + paint
//  helpers; §20.4 no dead buttons.
//

import SwiftUI

// MARK: - Lifecycle stages

private enum BOLStage: CaseIterable {
    case uploaded, verified, signed, filed

    var label: String {
        switch self {
        case .uploaded: return "UPLOADED"
        case .verified: return "VERIFIED"
        case .signed:   return "SIGNED"
        case .filed:    return "FILED"
        }
    }

    /// Derive the lifecycle anchor from the live `documents.getAll`
    /// `status` string. Unknown / missing → uploaded (the floor) so the
    /// strip never invents a later stage than the backend reports.
    static func from(status: String?) -> BOLStage {
        switch (status ?? "").lowercased() {
        case let s where s.contains("file"):                 return .filed
        case let s where s.contains("sign"):                 return .signed
        case let s where s.contains("verif") || s.contains("valid"): return .verified
        default:                                             return .uploaded
        }
    }
}

// MARK: - Screen root

struct ShipperBOLUpload: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var inAppLink: EusoSafariLink? = nil

    @State private var bol: DocumentsAPI.Document? = nil
    @State private var bolCount: Int = 0
    @State private var loading = true
    @State private var loadError: String? = nil

    init(loadId: String = "") {
        self.loadId = loadId
    }

    private let titleText = "BOL detail"

    // §15.3 audit-trail suffix — derived from the LIVE document id when
    // present, otherwise from the supplied loadId, otherwise honest "—".
    private var bolId: String {
        if let id = bol?.id, !id.isEmpty { return id }
        if !loadId.isEmpty {
            let suffix = loadId.replacingOccurrences(of: "LD-", with: "")
            return "BOL-\(suffix)"
        }
        return "—"
    }

    private var activeStage: BOLStage { BOLStage.from(status: bol?.status) }

    private var counterEyebrow: String {
        bolCount > 0 ? "\(bolCount) BOL" : "—"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                crumbRow
                    .padding(.top, Space.s2)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)

                content
            }
        }
        .task { await load() }
        .sheet(item: $inAppLink) { link in
            EusoInAppSafari(url: link.url).ignoresSafeArea()
        }
    }

    // MARK: Content states (mirror 300_DocumentsAll)

    @ViewBuilder
    private var content: some View {
        if loading {
            loadingCard
                .padding(.horizontal, Space.s3)
                .padding(.top, Space.s4)
        } else if let err = loadError {
            errorCard(err)
                .padding(.horizontal, Space.s3)
                .padding(.top, Space.s4)
        } else if let doc = bol {
            loadedBody(doc)
        } else {
            EusoEmptyState(
                systemImage: "doc.text",
                title: "No BOLs yet",
                subtitle: "Bills of lading appear here once a load is tendered and the BOL is uploaded."
            )
            .padding(.horizontal, Space.s3)
            .padding(.top, Space.s5)
        }
    }

    private var loadingCard: some View {
        cardShell {
            Text("Loading BOL…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(Space.s4)
        }
    }

    private func errorCard(_ message: String) -> some View {
        cardShell {
            Text(message)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
                .padding(Space.s4)
        }
    }

    @ViewBuilder
    private func loadedBody(_ doc: DocumentsAPI.Document) -> some View {
        heroCard(doc)
            .padding(.horizontal, Space.s3)
            .padding(.top, Space.s4)

        kpiQuartet(doc)
            .padding(.horizontal, Space.s3)
            .padding(.top, Space.s4)

        // EUSO-2148 — no signatory endpoint. Honest empty state, never
        // fabricated party rows.
        sectionLabel("SIGNATORIES")
            .padding(.top, Space.s5)

        signatoriesUnavailable
            .padding(.horizontal, Space.s3)
            .padding(.top, Space.s3)

        viewAuditTrailLink
            .padding(.horizontal, Space.s3)
            .padding(.top, Space.s4)

        Color.clear.frame(height: 96)
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · BOL UPLOAD")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(bolCount > 0 ? Brand.success : palette.textTertiary)
                .accessibilityLabel(bolCount > 0 ? "\(bolCount) bills of lading" : "No bills of lading")
        }
        .padding(.horizontal, Space.s3)
    }

    // MARK: Back chevron + breadcrumb

    private var crumbRow: some View {
        Button(action: tapBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("Loads")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, Space.s3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to Loads")
    }

    private func tapBack() {
        dismiss()
        NotificationCenter.default.post(
            name: .eusoShipperBolUploadBack,
            object: nil,
            userInfo: ["source": "229_ShipperBOLUpload", "loadId": loadId]
        )
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleText)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text(titleSubline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
    }

    private var titleSubline: String {
        if let doc = bol {
            return "\(dashIfEmpty(doc.name)) · \(dashIfEmpty(doc.category)) · \(humanISO(doc.uploadedAt, format: "MMM d"))"
        }
        return "Bills of lading for your tendered loads"
    }

    // MARK: Section label

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s3)
    }

    // MARK: Card shell

    @ViewBuilder
    private func cardShell<Content: View>(@ViewBuilder _ inner: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { inner() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Hero BOL card (live)

    private func heroCard(_ doc: DocumentsAPI.Document) -> some View {
        let statusUpper = doc.status.isEmpty ? "—" : doc.status.uppercased()
        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(LinearGradient.bolSuccessGrad)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(bolId)
                        .font(EType.mono(.micro))
                        .tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Text(statusUpper)
                        .font(EType.micro)
                        .tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 20)
                        .background(Capsule().fill(LinearGradient.bolSuccessGrad))
                }
                .padding(.top, Space.s4)

                Text(dashIfEmpty(doc.name))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .padding(.top, Space.s2 + 2)

                // Lane + spec are NOT in the documents.getAll projection
                // (EUSO-2147). Honest em-dash, no fabricated lane.
                Text("Lane — · spec — (EUSO-2147)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.top, 4)

                uploadedAtRow(doc)
                    .padding(.top, Space.s2 + 2)

                LifecycleStrip4BOL(activeStage: activeStage)
                    .padding(.top, Space.s4 + 2)
                    .padding(.bottom, Space.s4)
            }
            .padding(.leading, Space.s4)
            .padding(.trailing, Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bolId), \(statusUpper), \(dashIfEmpty(doc.name))")
    }

    private func uploadedAtRow(_ doc: DocumentsAPI.Document) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 0) {
                Text("Uploaded ").foregroundStyle(palette.textSecondary)
                Text(humanISO(doc.uploadedAt)).fontWeight(.bold).foregroundStyle(palette.textPrimary)
            }
            .font(.system(size: 10.5))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
        }
    }

    // MARK: KPI quartet (live SIZE; others honest em-dash)

    private func kpiQuartet(_ doc: DocumentsAPI.Document) -> some View {
        HStack(spacing: 0) {
            // PAGES not in projection → honest "—" w/ gap ref.
            kpiCellView(label: "PAGES", value: "—", style: .primary, sub: "EUSO-2147")
            kpiDivider
            // SIZE is live.
            kpiCellView(label: "SIZE", value: humanBytes(doc.size), style: .gradient, sub: "on file")
            kpiDivider
            // INTEGRITY hash not in projection → honest "—".
            kpiCellView(label: "INTEGRITY", value: "—", style: .primary, sub: "SHA-256")
            kpiDivider
            // No signatory endpoint (EUSO-2148) → honest "—".
            kpiCellView(label: "SIGNED", value: "—", style: .primary, sub: "EUSO-2148")
        }
        .padding(.vertical, Space.s4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 44)
    }

    private enum KpiStyle { case gradient, primary, warn }

    @ViewBuilder
    private func kpiCellView(label: String, value: String, style: KpiStyle, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                switch style {
                case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                case .primary:  Text(value).foregroundStyle(palette.textPrimary)
                case .warn:     Text(value).foregroundStyle(Brand.warning)
                }
            }
            .font(.system(size: 22, weight: .bold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(sub)
                .font(.system(size: 9))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private func humanBytes(_ bytes: Int) -> String {
        guard bytes > 0 else { return "—" }
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var idx = 0
        while value >= 1024 && idx < units.count - 1 {
            value /= 1024
            idx += 1
        }
        return idx == 0 ? "\(bytes) B" : String(format: "%.1f %@", value, units[idx])
    }

    // MARK: Signatories — honest unavailable state (EUSO-2148)

    private var signatoriesUnavailable: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(palette.textTertiary)
                .frame(width: 3)
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Signatory state not available")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("Per-party signing (method · device · timestamp) ships with documents.bol.getSignatories · EUSO-2148")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: View audit trail link

    private var viewAuditTrailLink: some View {
        Button(action: tapAuditTrail) {
            Text("View audit trail · SHA-256 chain")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LinearGradient.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func tapAuditTrail() {
        NotificationCenter.default.post(
            name: .eusoShipperBolAuditTrail,
            object: nil,
            userInfo: [
                "source": "229_ShipperBOLUpload",
                "bolId": bolId
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/bol/\(bolId)/audit-trail") {
            inAppLink = EusoSafariLink(url: url)
        }
    }

    // MARK: Load (mirror 300_DocumentsAll proc-call pattern)

    private func load() async {
        loading = true; loadError = nil
        do {
            let docs = try await EusoTripAPI.shared.documents.getAll(category: "BOL")
            bolCount = docs.count
            // Prefer the BOL whose name carries the supplied loadId
            // anchor; otherwise surface the first (most-recent) BOL.
            if !loadId.isEmpty {
                bol = docs.first(where: { $0.name.localizedCaseInsensitiveContains(loadId) }) ?? docs.first
            } else {
                bol = docs.first
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - 4-stage BOL lifecycle strip (file-scoped per §19.2)

private struct LifecycleStrip4BOL: View {
    let activeStage: BOLStage
    @Environment(\.palette) var palette

    private let stages: [(key: BOLStage, label: String)] = [
        (.uploaded, "UPLOADED"),
        (.verified, "VERIFIED"),
        (.signed,   "SIGNED"),
        (.filed,    "FILED"),
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
        let approxWidth: CGFloat = CGFloat(label.count) * 4.0
        let baseX = stride * CGFloat(i)
        if i == 0 { return baseX }
        if i == count - 1 { return baseX - approxWidth }
        return baseX - approxWidth / 2
    }
}

// MARK: - File-scoped paint extensions (§19.2)

private extension LinearGradient {
    /// Success gradient for the BOL hero rim + status pill.
    static let bolSuccessGrad = LinearGradient(
        colors: [Brand.success, Color(hex: 0x00A07B)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Warn gradient for receiver-pending tier rim.
    static let bolWarnGrad = LinearGradient(
        colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Back chevron on BOL Upload detail.
    static let eusoShipperBolUploadBack = Notification.Name("eusoShipperBolUploadBack")
    /// "View audit trail" gradient mid-link tap.
    static let eusoShipperBolAuditTrail = Notification.Name("eusoShipperBolAuditTrail")
}

// MARK: - Previews

#Preview("229 · BOL Upload · Dark") {
    ShipperBOLUpload()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("229 · BOL Upload · Light") {
    ShipperBOLUpload()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
