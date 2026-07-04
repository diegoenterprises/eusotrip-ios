//
//  523_DispatcherBhBolSignedCard.swift
//  EusoTrip — Dispatcher · BH lifecycle 523 · BOL signed (executed document surface).
//
//  Wireframe slot: 04 Dispatcher / 523 Dispatcher BH Bol Signed Card (Light+Dark SVG,
//  golden re-port 2026-06-25 — replaces the stamped Dpch800 duodecet body for this id).
//  Composition (SVG-verbatim): executed-document hero (BOL header + paper panel with the
//  signed-state seal + capture record) → SIGNED / PARTIES / POD KPI triple → execution-
//  record card → POD-clean strip → CTA pair (View executed BOL / Share copy).
//
//  Wiring manifest (code-traced against frontend/server/routers):
//    READ  loads.getById                          — load + parties + stage.
//    READ  documentManagement.getDocuments        — BOL + POD documents on this load.
//    READ  documentManagement.getDocumentById     — executed-document detail sheet.
//    READ  documentManagement.getAuditTrail       — execution audit entries (per document).
//    SHARE ShareLink                              — absolute document link when one exists.
//  Honest gaps (no server surface — rendered as data-absence states, never faked):
//    · signer identity + signature hash on the board read (the capture record lives with
//      the signature request, which isn't listable by load — surfaced as not recorded here)
//    · temp-trace-to-packet attach (carried from the pre-sign stage)
//
//  Dispatcher nav HOME·BOARD·[orb]·COMMS·ME, BOARD active. Light+Dark palette tokens only.
//

import SwiftUI

// MARK: - Screen

struct DispatcherBHBolSigned523Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            BH523Body(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",                    isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",                  isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct BH523Body: View {
    let loadId: String

    @Environment(\.palette) private var palette
    @Environment(\.dispatchNavHandler) private var navHandler

    @State private var load: LoadsAPI.LoadDetail?
    @State private var bolDoc: BH523Doc?
    @State private var podDoc: BH523Doc?
    @State private var docsLoaded = false
    @State private var auditCount: Int?
    @State private var loadFailed = false
    @State private var showDocSheet = false
    @State private var docDetail: BH523Doc?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrowRow
                titleRow
                Rectangle().fill(palette.iridescentHairline).frame(height: 1)
                heroCard
                kpiTriple
                sectionLabel("EXECUTION RECORD")
                executionRecord
                podStrip
                if loadFailed {
                    LifecycleCard(accentWarning: true) {
                        Text("Couldn't reach the document vault for this load. Everything shown is the last loaded state — pull to refresh.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(isPresented: $showDocSheet) { BH523DocSheet(doc: docDetail) }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · BACKHAUL · BOL SIGNED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text("\(load?.loadNumber ?? "—") · \(load?.rateDisplay ?? "—")")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
        }
    }

    private var titleRow: some View {
        HStack(spacing: Space.s3) {
            Button { navHandler?("board") } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            Text("Signed").font(.system(size: 26, weight: .bold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                Button("Refresh") { Task { await refresh() } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Hero — executed document

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BILL OF LADING")
                        .font(.system(size: 11, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(headerLine)
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                BH523Chip(text: executedChip.0, tint: executedChip.1)
            }
            // Paper panel — signed-copy state (never a fabricated signature stroke)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("RECEIVER SIGNATURE")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .center, spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let doc = signedDoc {
                            Text("Signed copy on file")
                                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text("\(doc.name ?? "delivery receipt") · open the executed document to view the ink")
                                .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                        } else if docsLoaded {
                            Text("No signed copy on file yet")
                                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text("the executed document lands here the moment the receiver inks it")
                                .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                        } else {
                            Text("—").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        }
                    }
                    Spacer()
                    Circle()
                        .strokeBorder(signedDoc != nil ? Brand.success : palette.borderStrong, lineWidth: 2)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: signedDoc != nil ? "checkmark" : "hourglass")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(signedDoc != nil ? Brand.success : palette.textTertiary)
                        )
                }
                Divider().overlay(palette.borderFaint)
                Text(captureLine)
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft, lineWidth: 1))
            HStack {
                Text(signedDoc != nil ? "Signed copy in the packet" : "Awaiting the signed copy")
                    .font(EType.mono(.micro))
                    .foregroundStyle(signedDoc != nil ? Brand.success : palette.textSecondary)
                Spacer()
                Text(signedDoc != nil ? "ON FILE" : "PENDING")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(signedDoc != nil ? Brand.success : Brand.warning)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.5), Brand.magenta.opacity(0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }

    // MARK: KPI triple — SIGNED / PARTIES / POD

    private var kpiTriple: some View {
        HStack(spacing: Space.s2) {
            BH523Kpi(label: "SIGNED",
                     value: signedTimeText,
                     sub: signedTimeText == "—" ? "no signed copy on file" : "copy filed",
                     tint: nil)
            BH523Kpi(label: "PARTIES",
                     value: "—",
                     sub: "signer roster isn't listable by load on this board",
                     tint: nil)
            BH523Kpi(label: "POD",
                     value: podDoc != nil ? "on file" : (docsLoaded ? "missing" : "—"),
                     sub: podDoc != nil ? "delivery receipt attached" : "no delivery receipt attached",
                     tint: podDoc != nil ? Brand.success : Brand.warning)
        }
    }

    // MARK: Execution record

    private var executionRecord: some View {
        LifecycleCard {
            VStack(spacing: 0) {
                BH523RecordRow(title: "Signer", value: "not recorded on this board")
                Divider().overlay(palette.borderFaint)
                BH523RecordRow(title: "Signed at", value: signedTimestampFull)
                Divider().overlay(palette.borderFaint)
                BH523RecordRow(title: "Hash", value: "not exposed to this board")
                Divider().overlay(palette.borderFaint)
                BH523RecordRow(title: "Audit", value: auditValue)
            }
        }
    }

    // MARK: POD strip

    private var podStrip: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: Space.s2) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(podDoc != nil ? Brand.success : palette.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(podDoc != nil ? "POD on file" : "POD not yet filed")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text(podDoc != nil
                         ? "exceptions aren't reported on this record · no temperature trace attached"
                         : "the delivery receipt attaches to this packet when it's captured")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                BH523Chip(text: podDoc != nil ? "ON FILE" : "—", tint: podDoc != nil ? Brand.success : Brand.neutral)
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                docDetail = signedDoc ?? bolDoc
                showDocSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye").font(.system(size: 13, weight: .bold))
                    Text("View executed BOL").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            if let shareURL {
                ShareLink(item: shareURL) {
                    Text("Share copy").font(EType.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(palette.textPrimary)
                        .background(Capsule().fill(palette.bgCard))
                        .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    docDetail = nil
                    showDocSheet = true
                } label: {
                    Text("Share copy").font(EType.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(palette.textTertiary)
                        .background(Capsule().fill(palette.bgCard))
                        .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Space.s2)
    }

    // MARK: Derived display

    /// The best "executed" document on the load: an approved BOL, else the POD, else the BOL.
    private var signedDoc: BH523Doc? {
        if bolDoc?.status?.lowercased() == "approved" { return bolDoc }
        return podDoc ?? (bolDoc?.status?.lowercased() == "signed" ? bolDoc : nil)
    }

    private var headerLine: String {
        var parts: [String] = []
        if let n = bolDoc?.name { parts.append(n) }
        parts.append(podDoc != nil ? "POD on file" : "POD pending")
        return parts.joined(separator: " · ")
    }

    private var executedChip: (String, Color) {
        guard docsLoaded else { return ("—", Brand.neutral) }
        if signedDoc != nil { return ("EXECUTED", Brand.success) }
        if bolDoc != nil { return ("AWAITING INK", Brand.warning) }
        return ("NO BOL", Brand.warning)
    }

    private var captureLine: String {
        if let iso = signedDoc?.uploadedAt, let d = bh523ISODate(iso) {
            let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"
            return "Filed \(f.string(from: d)) · capture details ride with the signature record"
        }
        return "Capture timestamp, signer, and hash ride with the signature record"
    }

    private var signedTimeText: String {
        guard let iso = signedDoc?.uploadedAt, let d = bh523ISODate(iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private var signedTimestampFull: String {
        guard let iso = signedDoc?.uploadedAt, let d = bh523ISODate(iso) else { return "no signed copy on file" }
        let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"
        return f.string(from: d)
    }

    private var auditValue: String {
        guard let n = auditCount else { return "—" }
        return n > 0 ? "recorded · \(n) entr\(n == 1 ? "y" : "ies")" : "no entries yet"
    }

    private var shareURL: URL? {
        guard let path = signedDoc?.url ?? bolDoc?.url else { return nil }
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        return EusoTripAPI.shared.baseURL.flatMap { URL(string: path, relativeTo: $0)?.absoluteURL }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            .padding(.top, Space.s1)
    }

    // MARK: Data

    private func refresh() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
            loadFailed = false
        } catch { loadFailed = load == nil }
        await fetchDocs()
        await fetchAudit()
    }

    private func fetchDocs() async {
        struct In: Encodable { let entityType: String; let entityId: String; let page: Int; let pageSize: Int }
        struct Out: Decodable { let documents: [BH523Doc]? }
        let numericId = (load?.id ?? loadId).replacingOccurrences(of: "load_", with: "")
        do {
            let out: Out = try await EusoTripAPI.shared.query(
                "documentManagement.getDocuments",
                input: In(entityType: "load", entityId: numericId, page: 1, pageSize: 50))
            let docs = out.documents ?? []
            bolDoc = docs.first(where: { $0.type == "bol" })
            podDoc = docs.first(where: { $0.type == "pod" || $0.type == "delivery_receipt" })
            docsLoaded = true
        } catch { docsLoaded = false }
    }

    private func fetchAudit() async {
        guard let docId = (signedDoc ?? bolDoc)?.id else { auditCount = nil; return }
        struct In: Encodable { let documentId: String; let page: Int; let pageSize: Int }
        struct Out: Decodable { let total: Int? }
        do {
            let out: Out = try await EusoTripAPI.shared.query(
                "documentManagement.getAuditTrail",
                input: In(documentId: docId, page: 1, pageSize: 1))
            auditCount = out.total
        } catch { auditCount = nil }
    }
}

// MARK: - Executed-document sheet

private struct BH523DocSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let doc: BH523Doc?

    var body: some View {
        ZStack {
            palette.bgPrimary.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("Executed document").font(EType.h2).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                if let d = doc {
                    LifecycleCard {
                        row("Name", d.name ?? "—")
                        row("Type", (d.type ?? "—").replacingOccurrences(of: "_", with: " ").uppercased())
                        row("Status", (d.status ?? "—").replacingOccurrences(of: "_", with: " ").capitalized)
                        row("Filed", d.uploadedAt ?? "—")
                    }
                    if let path = d.url,
                       let url = URL(string: path, relativeTo: EusoTripAPI.shared.baseURL)?.absoluteURL {
                        SwiftUI.Link(destination: url) {
                            Text("Open the filed copy").font(EType.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(.white)
                                .background(LinearGradient.diagonal)
                                .clipShape(Capsule())
                        }
                    }
                } else {
                    LifecycleCard(accentWarning: true) {
                        Text("No executed BOL is on file for this load yet — it lands here the moment the receiver signs.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(Space.s4)
        }
        .presentationDetents([.medium])
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value).font(EType.mono(.caption)).foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Small primitives

private struct BH523Chip: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
    }
}

private struct BH523Kpi: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let sub: String
    let tint: Color?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 20, weight: .heavy).monospacedDigit())
                .foregroundStyle(tint ?? palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

private struct BH523RecordRow: View {
    @Environment(\.palette) private var palette
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Text(value).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - File-local decode + helpers

private struct BH523Doc: Decodable {
    let id: String?
    let name: String?
    let type: String?
    let status: String?
    let url: String?
    let uploadedAt: String?
}

private func bh523ISODate(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    return ISO8601DateFormatter().date(from: s)
}

// MARK: - Previews

#Preview("523 Signed · Dark") {
    DispatcherBHBolSigned523Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("523 Signed · Light") {
    DispatcherBHBolSigned523Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
