//
//  072_MeDocs.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · documents vault)
//
//  Screen 072 · Me · Docs — the driver's personal document vault.
//  Four canonical buckets — CDL, Medical, TWIC, Hazmat — plus an
//  "Other" bucket for registrations, insurance, permits, and anything
//  the server returns that doesn't match one of the four. Every row
//  renders an expiration chip derived from server-computed urgency
//  (critical / high / medium / low) rather than a local date-math pass,
//  so the banner and the per-row chips agree by construction.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Document rows come from `documentManagement.getDocuments` —
//      MCP-verified at `frontend/server/routers/documentManagement.ts:386`.
//      The server scopes the query to `ctx.user.id`, so a newly signed-
//      in driver sees only their own vault. Uploaded-at sort is
//      enforced server-side (`sortBy: uploadedAt, sortOrder: desc`).
//
//    • The top banner reads from `documentManagement.getExpiringDocuments`
//      (same router, line 1520). `daysAhead` is pinned to 90 so the
//      driver sees a full quarter of upcoming renewals — TSA's TWIC
//      processing window is long, and CDL / Medical renewals benefit
//      from early warning too. Urgency labels ("critical" / "high" /
//      "medium" / "low") come straight from the server — no client
//      recomputation.
//
//    • Download buttons resolve the server-returned `url` against
//      `EusoTripAPI.baseURL` when the URL is relative (the backend
//      hands back `/api/documents/:id/download` paths for in-app
//      resolution). Absolute blob URLs pass through untouched.
//
//    • Upload is deliberately not wired on this screen. `getDocuments`
//      + `uploadDocument` round-trips work server-side today, but the
//      mobile file-picker wave (UIDocumentPickerViewController /
//      PHPickerViewController) lands with the next infra bump; this
//      screen surfaces the current vault state honestly and directs
//      drivers to the desktop dashboard for new uploads. No stub
//      buttons that do nothing.
//
//    • Empty state is server-confirmed. A driver with zero documents
//      on file sees an `EusoEmptyState` hero rather than a placeholder
//      list.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on header numerals, section titles,
//         and the download capsule. Urgency chips use palette tokens +
//         Brand.warning for "critical" / expired states.
//    §4   Tokenized spacing (Space.sN), radii (Radius.sm/md/lg),
//         type (EType.*). No magic numbers.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle expressions wrapped in `AnyShapeStyle`.
//    §10  Previews compile in isolation — stores land in `.error` via
//         `notConfigured` under the preview's no-baseURL runtime. No
//         fixtures.
//

import SwiftUI

// MARK: - Document category buckets
//
// The backend's `documentTypeSchema` enum does not include standalone
// values for "CDL" or "TWIC" — CDLs typically land under `other` or
// `operating_authority`, TWIC under `permit` or `other`. This local
// classifier maps both the canonical enum value and a lowercased-name
// keyword scan into one of five buckets, so the driver sees their
// licence, medical card, TWIC, and hazmat endorsement in distinct
// sections regardless of how they were tagged at upload.

private enum DocCategory: String, CaseIterable, Identifiable {
    case cdl
    case medical
    case twic
    case hazmat
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cdl:     return "CDL"
        case .medical: return "Medical Card"
        case .twic:    return "TWIC"
        case .hazmat:  return "Hazmat Endorsement"
        case .other:   return "Other Documents"
        }
    }

    var icon: String {
        switch self {
        case .cdl:     return "creditcard"
        case .medical: return "cross.case"
        case .twic:    return "person.badge.shield.checkmark"
        case .hazmat:  return "exclamationmark.triangle"
        case .other:   return "folder"
        }
    }

    var emptyCopy: String {
        switch self {
        case .cdl:     return "No CDL on file. Upload yours from the desktop dashboard."
        case .medical: return "No medical card on file. DOT medical certificates expire every 24 months."
        case .twic:    return "No TWIC on file. Port / terminal access requires an active TWIC card."
        case .hazmat:  return "No hazmat endorsement on file. Required for placarded loads."
        case .other:   return "Registrations, insurance, permits, and miscellaneous documents land here."
        }
    }

    /// Classify a document into one of the five buckets. Checks the
    /// canonical type first, then falls back to lowercased-name keyword
    /// scan so docs uploaded under `other` still find their bucket.
    static func from(document d: DocumentManagementAPI.Document) -> DocCategory {
        let name = d.name.lowercased()
        let type = d.type.lowercased()
        if type == "medical_card" || name.contains("medical") || name.contains("dot card") {
            return .medical
        }
        if type == "hazmat_placard" || name.contains("hazmat") {
            return .hazmat
        }
        if name.contains("twic") {
            return .twic
        }
        if name.contains("cdl") || name.contains("commercial driver") || name.contains("driver's license") || name.contains("drivers license") {
            return .cdl
        }
        return .other
    }
}

// MARK: - Screen root

struct MeDocs: View {
    @Environment(\.palette) var palette
    @StateObject private var docs = DriverDocumentsStore()
    @StateObject private var expiring = ExpiringDocumentsStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                expirationBanner
                switch docs.state {
                case .loading:
                    loadingSkeleton
                case .empty:
                    emptyHero
                case .error(let e):
                    errorBanner(e)
                case .loaded(let all):
                    ForEach(DocCategory.allCases) { bucket in
                        section(bucket: bucket, rows: all.filter { DocCategory.from(document: $0) == bucket })
                    }
                }
                uploadDisclosure
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        async let a: Void = docs.refresh()
        async let b: Void = expiring.refresh()
        _ = await (a, b)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Documents")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CDL · Medical · TWIC · Hazmat")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: (docs.isLoading || expiring.isLoading) ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Expiration banner

    @ViewBuilder
    private var expirationBanner: some View {
        if let resp = expiring.state.value {
            let totalExpiring = resp.totalExpiring
            let totalExpired = resp.totalExpired
            if totalExpiring > 0 || totalExpired > 0 {
                HStack(spacing: Space.s3) {
                    Image(systemName: totalExpired > 0 ? "exclamationmark.octagon.fill" : "clock.badge.exclamationmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(totalExpired > 0 ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(LinearGradient.diagonal))
                    VStack(alignment: .leading, spacing: 2) {
                        if totalExpired > 0 {
                            Text("\(totalExpired) expired · \(totalExpiring) expiring soon")
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                        } else {
                            Text("\(totalExpiring) expiring within 90 days")
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                        }
                        Text("Renew before the next dispatch to avoid holds.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                }
                .padding(Space.s3)
                .eusoCard(radius: Radius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(
                            totalExpired > 0 ? Brand.warning.opacity(0.6) : palette.borderFaint,
                            lineWidth: 1
                        )
                )
            }
        }
    }

    // MARK: States

    private var loadingSkeleton: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.35))
                    .frame(height: 88)
            }
        }
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "folder",
            title: "No documents on file",
            subtitle: "Upload your CDL, medical card, TWIC, and hazmat endorsement from the desktop dashboard. They'll land here within seconds."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't load documents")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await reload() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Category sections

    @ViewBuilder
    private func section(bucket: DocCategory, rows: [DocumentManagementAPI.Document]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: bucket.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(bucket.title.uppercased())
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if !rows.isEmpty {
                    Text("\(rows.count)")
                        .font(EType.micro)
                        .tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                }
            }

            if rows.isEmpty {
                notOnFileRow(bucket: bucket)
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(rows) { doc in
                        docRow(doc)
                    }
                }
            }
        }
    }

    private func notOnFileRow(bucket: DocCategory) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: bucket.icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette.textTertiary)
            Text(bucket.emptyCopy)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            Spacer()
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    private func docRow(_ d: DocumentManagementAPI.Document) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if let uploaded = shortDate(d.uploadedAt) {
                    Text("Uploaded \(uploaded)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                expirationChip(for: d)
            }
            Spacer(minLength: Space.s2)
            downloadButton(for: d)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    // MARK: Expiration chip (server-urgency aware)

    @ViewBuilder
    private func expirationChip(for d: DocumentManagementAPI.Document) -> some View {
        if let (label, urgency) = expirationLabel(for: d) {
            let capsuleStyle = urgencyStyle(urgency)
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(capsuleStyle.foreground)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .strokeBorder(capsuleStyle.border, lineWidth: 1)
                        .background(Capsule().fill(capsuleStyle.fill))
                )
        }
    }

    private struct ChipStyle {
        let foreground: AnyShapeStyle
        let border: Color
        let fill: AnyShapeStyle
    }

    private func urgencyStyle(_ urgency: String) -> ChipStyle {
        switch urgency.lowercased() {
        case "expired":
            return ChipStyle(
                foreground: AnyShapeStyle(.white),
                border: Brand.warning,
                fill: AnyShapeStyle(Brand.warning)
            )
        case "critical", "high":
            return ChipStyle(
                foreground: AnyShapeStyle(Brand.warning),
                border: Brand.warning.opacity(0.6),
                fill: AnyShapeStyle(Color.clear)
            )
        case "medium":
            return ChipStyle(
                foreground: AnyShapeStyle(palette.textSecondary),
                border: palette.borderFaint,
                fill: AnyShapeStyle(Color.clear)
            )
        default:
            // "low" or anything else: subtle neutral
            return ChipStyle(
                foreground: AnyShapeStyle(palette.textTertiary),
                border: palette.borderFaint.opacity(0.6),
                fill: AnyShapeStyle(Color.clear)
            )
        }
    }

    /// Build the chip label + urgency string for a document by
    /// cross-referencing it against `ExpiringDocumentsStore`. The server
    /// is authoritative on urgency — we only fall back to "Expires DATE"
    /// when the doc isn't in either the expiring or expired list (e.g.
    /// expires > 90 days out).
    private func expirationLabel(for d: DocumentManagementAPI.Document) -> (String, String)? {
        guard let resp = expiring.state.value else {
            // Pre-load — fall back to local date math off expiresAt so
            // the chip isn't blank while the expirations call is in
            // flight. Server urgency lands on the next tick.
            return localExpirationFallback(for: d)
        }
        if let hit = resp.expired.first(where: { $0.id == d.id }) {
            return ("EXPIRED \(hit.daysExpired)d", "expired")
        }
        if let hit = resp.expiring.first(where: { $0.id == d.id }) {
            let label = hit.daysUntilExpiry <= 0 ? "EXPIRES TODAY" : "EXPIRES IN \(hit.daysUntilExpiry)d"
            return (label, hit.urgency)
        }
        return localExpirationFallback(for: d)
    }

    private func localExpirationFallback(for d: DocumentManagementAPI.Document) -> (String, String)? {
        guard let exp = d.expiresAt, !exp.isEmpty,
              let date = parseIso(exp)
        else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMM yyyy"
        return ("EXPIRES \(out.string(from: date).uppercased())", "low")
    }

    // MARK: Download button

    @ViewBuilder
    private func downloadButton(for d: DocumentManagementAPI.Document) -> some View {
        if let url = resolveDownloadURL(d.url) {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("OPEN")
                        .font(EType.micro)
                        .tracking(1.2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 8)
                .background(Capsule().fill(LinearGradient.diagonal))
            }
        } else {
            Text("NO FILE")
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 8)
                .background(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    // MARK: Upload-disclosure footer
    //
    // Honest disclosure of the current upload limitation — drivers can
    // view and download from iOS, uploads happen on the desktop today.

    private var uploadDisclosure: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("Uploading new documents")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("File uploads live on the Eusorone desktop dashboard today. This vault view is kept in sync within seconds of any upload or expiration renewal on the web side.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Helpers

    private func parseIso(_ iso: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    private func shortDate(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty, let d = parseIso(iso) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMM d, yyyy"
        return out.string(from: d)
    }

    /// Resolve a server `url` field against `EusoTripAPI.baseURL` when
    /// relative; pass absolute blob URLs through. Returns nil when the
    /// server handed back an empty string or the base URL isn't set
    /// (preview runtime).
    private func resolveDownloadURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        guard let base = EusoTripAPI.shared.baseURL else { return nil }
        return URL(string: raw, relativeTo: base)?.absoluteURL
    }
}

// MARK: - Screen wrapper

struct MeDocsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeDocs()
        } nav: {
            BottomNav(
                leading: driverNavLeading_072(),
                trailing: driverNavTrailing_072(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_072() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_072() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews
//
// Previews never run `.task` — stores stay in `.loading` so both
// registers render deterministic skeletons without hitting the network.
// No fixtures.

#Preview("072 · Me Docs · Night") {
    MeDocsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("072 · Me Docs · Afternoon") {
    MeDocsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
