//
//  322_CatalystDriverDocuments.swift
//  EusoTrip — Catalyst · Driver Documents (brick 322).
//
//  Pixel-faithful port of "322 Catalyst Driver Documents · Light/Dark"
//  (Figma `~/Desktop/EusoTrip 2027 UI Wireframes/03 Catalyst/Light-SVG/`).
//  The catalyst-side document vault for a single driver — the file
//  binaries behind 321 Driver Profile's credential-pill scanline
//  (CDL · MEDICAL · DQ FILE · MVR/DRUG). Web parity:
//  `/catalyst/drivers/[driverId]/documents`.
//
//  Catalyst↔Driver relationship per founder doctrine "no stubs / no
//  mock data — wired correctly":
//    • Every document row paints from a REAL DB record. We don't
//      synthesize "PDF placeholder" rows when the underlying
//      `documents` table is empty for this driver — empty roster
//      surfaces "No documents yet · upload to start the §391 vault"
//      with a real Add CTA.
//    • The §382 Drug-screen / §391.41 Medical / §383 CDL / §391.25
//      MVR taxonomy is enforced client-side via type-name matchers
//      (drug / medical / cdl / mvr) — same matcher 326 Driver
//      Compliance uses for its federal axis status. Cross-surface
//      §382 trinity continues here: vault (this screen) + workflow
//      (325) + regulatory (326) all read the SAME records.
//
//  Server wiring (all real, no stubs):
//    • `driverQualification.getDocuments(driverId)` — driver-scoped
//      file list ordered by createdAt desc, includes type / status /
//      uploadedAt / expiresAt.
//    • `driverQualification.getOverview(driverId)` — KPI strip
//      summary (total / valid / expiringSoon / expired / missing).
//    • `catalysts.getMyDrivers` — to default the screen to the
//      catalyst's primary driver when no `driverId` is passed.
//    • `driverQualification.uploadDocument` — fired by the Add CTA
//      via NotificationCenter so the catalyst-side upload sheet
//      can hand off to the existing flow.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen wrapper

struct CatalystDriverDocumentsScreen: View {
    let theme: Theme.Palette
    let driverId: String

    init(theme: Theme.Palette, driverId: String = "") {
        self.theme = theme
        self.driverId = driverId
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystDriverDocuments(initialDriverId: driverId)
        } nav: {
            BottomNav(
                leading: catalystNavLeading_322(),
                trailing: catalystNavTrailing_322(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_322() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_322() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - DQ taxonomy filter

private enum DocFilter: String, CaseIterable, Identifiable {
    case all     = "All"
    case cdl     = "CDL"
    case medical = "Medical"
    case mvr     = "MVR"
    case drug    = "Drug"
    case other   = "Other"

    var id: String { rawValue }

    /// Type-name matchers used to bucket documents. The same matcher
    /// 326 Driver Compliance uses for its federal axis status —
    /// keeping the §382 / §391.41 / §383 taxonomy consistent across
    /// surfaces.
    func matches(_ type: String) -> Bool {
        let t = type.lowercased()
        switch self {
        case .all:     return true
        case .cdl:     return t.contains("cdl") || t.contains("license")
        case .medical: return t.contains("medical")
        case .mvr:     return t.contains("mvr")
        case .drug:    return t.contains("drug") || t.contains("clearinghouse")
        case .other:
            return !(["cdl", "license", "medical", "mvr", "drug", "clearinghouse"]
                .contains { t.contains($0) })
        }
    }
}

// MARK: - Body

private struct CatalystDriverDocuments: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    let initialDriverId: String

    @State private var resolvedDriverId: String = ""
    @State private var resolvedDriverName: String = ""
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var documents: [DriverQualificationAPI.DQDocument] = []
    @State private var overview: DriverQualificationAPI.Overview? = nil
    @State private var filter: DocFilter = .all

    // MARK: Sheet state
    @State private var selectedDocument: DriverQualificationAPI.DQDocument? = nil
    @State private var showUploadSheet: Bool = false

    private var filteredDocuments: [DriverQualificationAPI.DQDocument] {
        documents.filter { filter.matches($0.type) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleRowWithUpload
                iridescentHairline
                ownerOpSeamBanner

                if loading {
                    skeletonBody
                } else if let err = loadError {
                    errorBanner(err)
                } else if !resolvedDriverId.isEmpty {
                    kpiStrip
                    filterChipsRow
                    sectionHeader
                    if filteredDocuments.isEmpty {
                        emptyForFilterState
                    } else {
                        documentsList
                    }
                } else {
                    emptyDriverState
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await loadAll() }
        // Server-side document upload / status changes fan out via
        // RealtimeService → `.esangRefreshSurface`.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll() }
        }
        .sheet(item: $selectedDocument) { doc in
            CatalystDocumentDetailSheet(
                document: doc,
                onMarkExpired: {
                    Task { await markDocumentExpired(doc) }
                }
            )
            .environment(\.palette, palette)
        }
        .sheet(isPresented: $showUploadSheet) {
            CatalystDocumentUploadSheet(
                driverId: resolvedDriverId,
                presetType: filter == .all ? nil : filter,
                onUploaded: {
                    showUploadSheet = false
                    Task { await loadAll() }
                }
            )
            .environment(\.palette, palette)
        }
    }

    // MARK: - Document mutations

    private func markDocumentExpired(_ doc: DriverQualificationAPI.DQDocument) async {
        do {
            _ = try await EusoTripAPI.shared.dq.updateDocument(
                documentId: doc.id,
                status: "expired"
            )
            selectedDocument = nil
            await loadAll()
        } catch {
            // Surface via the error banner pattern; keep sheet open.
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - TopBar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DRIVER · DOCUMENTS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text(counterLabel)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var counterLabel: String {
        let total = documents.count
        let valid = documents.filter { ($0.status?.lowercased() == "valid") }.count
        return "\(valid) VALID · \(total) ON FILE"
    }

    private var titleRowWithUpload: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Driver documents")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Text(subtitleLine)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                showUploadSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .heavy))
                    Text("Upload")
                        .font(.system(size: 12, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var subtitleLine: String {
        let name = resolvedDriverName.isEmpty ? "—" : resolvedDriverName
        return "Eusotrans LLC · \(name) · 49 CFR §391 vault"
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: - Owner-op seam banner

    private var ownerOpSeamBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text("OWNER-OP SEAM · §391 CLEAN BOOKS")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Same companyId both sides · vault auto-syncs to driver self-service")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            LinearGradient(
                colors: [Brand.blue.opacity(0.10), Brand.magenta.opacity(0.10)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [Brand.blue.opacity(0.40), Brand.magenta.opacity(0.40)],
                    startPoint: .leading, endPoint: .trailing
                ), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: 0) {
            kpiCell(
                eyebrow: "VALID",
                value: overview.map { "\($0.documents.valid)" } ?? "—",
                meta: "on file",
                emphasis: .success
            )
            kpiDivider
            kpiCell(
                eyebrow: "EXPIRING",
                value: overview.map { "\($0.documents.expiringSoon)" } ?? "—",
                meta: "≤ 30d",
                emphasis: .warning
            )
            kpiDivider
            kpiCell(
                eyebrow: "EXPIRED",
                value: overview.map { "\($0.documents.expired)" } ?? "—",
                meta: "action req",
                emphasis: overview.map { $0.documents.expired > 0 ? .danger : .neutral } ?? .neutral
            )
            kpiDivider
            kpiCell(
                eyebrow: "SCORE",
                value: overview.map { "\($0.complianceScore)%" } ?? "—",
                meta: "DQ compliance",
                emphasis: .gradient
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Brand.blue, Brand.magenta],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private enum KPIEmphasis { case neutral, success, warning, danger, gradient }

    private func kpiCell(eyebrow: String, value: String, meta: String, emphasis: KPIEmphasis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                switch emphasis {
                case .gradient: Text(value).font(.system(size: 18, weight: .heavy)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                case .success:  Text(value).font(.system(size: 18, weight: .heavy)).monospacedDigit().foregroundStyle(Brand.success)
                case .warning:  Text(value).font(.system(size: 18, weight: .heavy)).monospacedDigit().foregroundStyle(Brand.warning)
                case .danger:   Text(value).font(.system(size: 18, weight: .heavy)).monospacedDigit().foregroundStyle(Brand.danger)
                case .neutral:  Text(value).font(.system(size: 18, weight: .heavy)).monospacedDigit().foregroundStyle(palette.textPrimary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(meta)
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 38)
            .padding(.horizontal, 4)
    }

    // MARK: - Filter chips

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DocFilter.allCases) { f in
                    filterChip(f)
                }
            }
        }
    }

    private func filterChip(_ f: DocFilter) -> some View {
        let active = filter == f
        let count = documents.filter { f.matches($0.type) }.count
        return Button {
            withAnimation(.easeOut(duration: 0.12)) { filter = f }
        } label: {
            Text("\(f.rawValue) · \(count)")
                .font(.system(size: 12, weight: active ? .heavy : .semibold))
                .foregroundStyle(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(active ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        active ? AnyShapeStyle(Color.clear) : AnyShapeStyle(palette.borderFaint),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section header + list

    private var sectionHeader: some View {
        Text(sectionHeaderLabel)
            .font(.system(size: 9, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
    }

    private var sectionHeaderLabel: String {
        let total = filteredDocuments.count
        let scope = filter == .all ? "ALL" : filter.rawValue.uppercased()
        return "\(total) \(scope) · NEWEST FIRST · 49 CFR §391"
    }

    private var documentsList: some View {
        VStack(spacing: 8) {
            ForEach(filteredDocuments) { doc in
                Button {
                    selectedDocument = doc
                } label: {
                    documentRow(doc)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func documentRow(_ doc: DriverQualificationAPI.DQDocument) -> some View {
        let stat = docStatus(doc)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: docIcon(doc))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(stat.tint)
                .frame(width: 40, height: 40)
                .background(stat.tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.name?.isEmpty == false ? doc.name! : prettyType(doc.type))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(typeRegLine(doc))
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                Text(uploadedLine(doc))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(stat.label)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(stat.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stat.tint.opacity(0.12))
                    .clipShape(Capsule())
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(12)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private struct DocStatus { let label: String; let tint: Color }

    private func docStatus(_ doc: DriverQualificationAPI.DQDocument) -> DocStatus {
        let s = (doc.status ?? "").lowercased()
        switch s {
        case "valid":         return DocStatus(label: "VALID",    tint: Brand.success)
        case "expiring_soon": return DocStatus(label: "EXP SOON", tint: Brand.warning)
        case "expired":       return DocStatus(label: "EXPIRED",  tint: Brand.danger)
        case "missing":       return DocStatus(label: "MISSING",  tint: Brand.danger)
        case "pending":       return DocStatus(label: "PENDING",  tint: Brand.info)
        default:               return DocStatus(label: s.uppercased().isEmpty ? "—" : s.uppercased(), tint: palette.textTertiary)
        }
    }

    private func docIcon(_ doc: DriverQualificationAPI.DQDocument) -> String {
        let t = doc.type.lowercased()
        if t.contains("cdl") || t.contains("license") { return "rectangle.fill.on.rectangle.fill" }
        if t.contains("medical")                       { return "cross.case.fill" }
        if t.contains("mvr")                           { return "list.bullet.clipboard.fill" }
        if t.contains("drug") || t.contains("clearinghouse") { return "testtube.2" }
        if t.contains("hazmat")                        { return "diamond.fill" }
        if t.contains("twic")                          { return "wallet.pass.fill" }
        if t.contains("road")                          { return "checkmark.seal.fill" }
        if t.contains("annual")                        { return "calendar" }
        return "doc.text.fill"
    }

    private func prettyType(_ t: String) -> String {
        t.replacingOccurrences(of: "_", with: " ")
         .split(separator: " ")
         .map { $0.prefix(1).uppercased() + $0.dropFirst() }
         .joined(separator: " ")
    }

    private func typeRegLine(_ doc: DriverQualificationAPI.DQDocument) -> String {
        let pretty = prettyType(doc.type)
        let reg = doc.regulation?.isEmpty == false ? " · \(doc.regulation!)" : regulationFor(doc.type)
        return "\(pretty)\(reg)"
    }

    private func regulationFor(_ type: String) -> String {
        let t = type.lowercased()
        if t.contains("cdl") || t.contains("license") { return " · 49 CFR §383" }
        if t.contains("medical")                       { return " · 49 CFR §391.41" }
        if t.contains("mvr")                           { return " · 49 CFR §391.25" }
        if t.contains("drug") || t.contains("clearinghouse") { return " · 49 CFR §382" }
        if t.contains("hazmat")                        { return " · 49 CFR §383.93" }
        if t.contains("twic")                          { return " · 49 CFR §1572" }
        if t.contains("road")                          { return " · 49 CFR §391.31" }
        if t.contains("annual")                        { return " · 49 CFR §391.25" }
        return ""
    }

    private func uploadedLine(_ doc: DriverQualificationAPI.DQDocument) -> String {
        let uploaded = doc.uploadedAt?.isEmpty == false ? "uploaded \(formatDate(doc.uploadedAt!))" : "no upload date"
        let exp = doc.expiresAt?.isEmpty == false ? " · expires \(formatDate(doc.expiresAt!))" : ""
        return "\(uploaded)\(exp)"
    }

    private func formatDate(_ raw: String) -> String {
        if raw.count >= 10 { return String(raw.prefix(10)) }
        return raw
    }

    // MARK: - Empty / loading / error

    private var skeletonBody: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCard).frame(height: 80)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard).frame(height: 28)
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard).frame(height: 72)
            }
        }
        .redacted(reason: .placeholder)
    }

    @ViewBuilder
    private var emptyDriverState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text("No driver to view")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Add a driver to your roster on 304 Fleet Drivers to start the §391 document vault.")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var emptyForFilterState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text(emptyForFilterTitle)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(emptyForFilterMeta)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button {
                showUploadSheet = true
            } label: {
                Text("Upload \(filter.rawValue)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var emptyForFilterTitle: String {
        if documents.isEmpty { return "No documents yet" }
        return "No \(filter.rawValue) documents"
    }

    private var emptyForFilterMeta: String {
        if documents.isEmpty {
            return "Upload to start the §391 driver-qualification vault. Categories: CDL · Medical · MVR · Drug · Hazmat · TWIC."
        }
        return "Switch the filter or upload a \(filter.rawValue) record to fill the gap."
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(msg)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Button { Task { await loadAll() } } label: {
                    Text("Retry")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Brand.danger.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Network

    private func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            if !initialDriverId.isEmpty {
                resolvedDriverId = initialDriverId
                let roster = (try? await EusoTripAPI.shared.catalyst.getMyDrivers(limit: 50)) ?? []
                resolvedDriverName = roster.first { $0.id == initialDriverId }?.name ?? ""
            } else {
                let roster = try await EusoTripAPI.shared.catalyst.getMyDrivers(limit: 50)
                guard let primary = roster.first else { return }
                resolvedDriverId = primary.id
                resolvedDriverName = primary.name
            }
            async let docsTask: [DriverQualificationAPI.DQDocument] = {
                (try? await EusoTripAPI.shared.dq.getDocuments(driverId: resolvedDriverId))?.documents ?? []
            }()
            async let overviewTask: DriverQualificationAPI.Overview? = {
                try? await EusoTripAPI.shared.dq.getOverview(driverId: resolvedDriverId)
            }()
            let (d, o) = await (docsTask, overviewTask)
            self.documents = d
            self.overview = o
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Document detail sheet

private struct CatalystDocumentDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let document: DriverQualificationAPI.DQDocument
    let onMarkExpired: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Type") {
                    LabeledRow(label: "Type", value: prettyType(document.type))
                    LabeledRow(label: "Status", value: (document.status ?? "—").uppercased())
                    if let reg = document.regulation, !reg.isEmpty {
                        LabeledRow(label: "Regulation", value: reg)
                    }
                }
                Section("Name") {
                    Text(document.name?.isEmpty == false ? document.name! : prettyType(document.type))
                        .foregroundStyle(palette.textPrimary)
                }
                Section("Dates") {
                    LabeledRow(label: "Uploaded", value: formatDate(document.uploadedAt))
                    LabeledRow(label: "Expires", value: formatDate(document.expiresAt))
                }
                Section {
                    Button(role: .destructive) {
                        onMarkExpired()
                    } label: {
                        Label("Mark expired", systemImage: "xmark.octagon")
                    }
                }
            }
            .navigationTitle(prettyType(document.type))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func prettyType(_ t: String) -> String {
        t.replacingOccurrences(of: "_", with: " ")
         .split(separator: " ")
         .map { $0.prefix(1).uppercased() + $0.dropFirst() }
         .joined(separator: " ")
    }

    private func formatDate(_ raw: String?) -> String {
        guard let r = raw, !r.isEmpty else { return "—" }
        if r.count >= 10 { return String(r.prefix(10)) }
        return r
    }
}

private struct LabeledRow: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Document upload sheet (metadata)

private struct CatalystDocumentUploadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let driverId: String
    let presetType: DocFilter?
    let onUploaded: () -> Void

    @State private var docName: String = ""
    @State private var docType: DQUploadType = .cdl
    @State private var expiresAt: Date = Date().addingTimeInterval(60 * 60 * 24 * 365)
    @State private var hasExpiry: Bool = true
    @State private var notes: String = ""
    @State private var uploading: Bool = false
    @State private var uploadError: String? = nil

    enum DQUploadType: String, CaseIterable, Identifiable {
        case cdl, medical, mvr, drug, hazmat, twic, annualReview, other

        var id: String { rawValue }
        var label: String {
            switch self {
            case .cdl: return "CDL"
            case .medical: return "Medical"
            case .mvr: return "MVR"
            case .drug: return "Drug screen"
            case .hazmat: return "Hazmat endorsement"
            case .twic: return "TWIC"
            case .annualReview: return "Annual review"
            case .other: return "Other"
            }
        }

        /// Server-side `dqDocumentTypeSchema` enum value.
        var serverValue: String {
            switch self {
            case .cdl: return "cdl"
            case .medical: return "medical_card"
            case .mvr: return "mvr"
            case .drug: return "drug_test"
            case .hazmat: return "hazmat"
            case .twic: return "twic"
            case .annualReview: return "annual_review"
            case .other: return "compliance"
            }
        }

        static func from(filter: DocFilter?) -> DQUploadType {
            switch filter {
            case .cdl: return .cdl
            case .medical: return .medical
            case .mvr: return .mvr
            case .drug: return .drug
            default: return .cdl
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Document type") {
                    Picker("Type", selection: $docType) {
                        ForEach(DQUploadType.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                }
                Section("Name") {
                    TextField("e.g. CDL-A IA-D08-441-922", text: $docName)
                }
                Section("Expiry") {
                    Toggle("Has expiration date", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Expires", selection: $expiresAt, displayedComponents: .date)
                    }
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
                if let err = uploadError {
                    Section {
                        Text(err)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.danger)
                    }
                }
            }
            .navigationTitle("Upload document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(uploading ? "Uploading…" : "Save") {
                        Task { await upload() }
                    }
                    .disabled(uploading || docName.isEmpty)
                }
            }
            .onAppear {
                if let preset = presetType {
                    docType = DQUploadType.from(filter: preset)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func upload() async {
        uploadError = nil
        uploading = true
        defer { uploading = false }

        let isoExpiry: String? = hasExpiry ? Self.iso8601Date(expiresAt) : nil
        do {
            _ = try await EusoTripAPI.shared.dq.uploadDocument(
                driverId: driverId,
                type: docType.serverValue,
                name: docName,
                expiresAt: isoExpiry,
                notes: notes.isEmpty ? nil : notes
            )
            onUploaded()
        } catch {
            uploadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func iso8601Date(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }
}

// MARK: - Previews

#Preview("322 · Catalyst · Driver Documents · Night") {
    CatalystDriverDocumentsScreen(theme: Theme.dark, driverId: "")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("322 · Catalyst · Driver Documents · Afternoon") {
    CatalystDriverDocumentsScreen(theme: Theme.light, driverId: "")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
