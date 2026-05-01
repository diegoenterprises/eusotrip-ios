//
//  106_MeEusoTickets.swift
//  EusoTrip 2027 UI — driver · Me · EusoTicket
//
//  EusoTicket = the per-haul paper trail: Bills of Lading, run tickets,
//  and the receipts (lumper / scale / fuel / toll) that ride with each
//  load. The web platform's `/euso-ticket` page (Terminal Manager +
//  Driver) already ships this surface; this brick is the iOS port so
//  drivers see the same picks they see on the dispatcher's screen
//  without reaching for a laptop.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Run tickets list ships from `eusoTicket.listRunTickets`
//      (MCP-verified at `frontend/server/routers/eusoTicket.ts:237`).
//    • BOLs ship from `eusoTicket.listBOLs` (line 442).
//    • PDF generation goes through `eusoTicket.generateRunTicketPDF` /
//      `generateBOLPDF` (lines 664 / 676). The mutation returns a
//      relative URL the iOS layer hands to SFSafariViewController.
//    • Status updates fire `updateRunTicketStatus` / `updateBOLStatus`.
//
//  Receipts are surfaced via the existing Documents Center (HubCategory
//  .loadDocs) so a single channel covers BOL / POD / lumper / scale /
//  fuel / toll / rate-con / detention / freight-bill etc — same docs
//  table, no parallel wiring.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on the action row + per-row PDF chip.
//    §4   Tokenized Space/Radius/EType throughout.
//    §5   Palette semantic.
//    §10  SwiftUI #Preview blocks for Dark + Light. No fixtures.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
import SafariServices
#endif

// MARK: - Store

@MainActor
final class EusoTicketsStore: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case tickets, bols
        var id: String { rawValue }
        var label: String {
            switch self {
            case .tickets: return "Run tickets"
            case .bols:    return "Bills of Lading"
            }
        }
    }

    enum LoadState {
        case loading
        case empty
        case error(String)
        case loaded(tickets: [EusoTicketAPI.RunTicketRow],
                    bols: [EusoTicketAPI.BOLRow])
    }

    @Published private(set) var state: LoadState = .loading
    /// id of the row currently mutating (PDF generation or status).
    /// Drives the spinner in the row chrome.
    @Published var mutatingId: String?
    @Published var lastToast: String?

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    func refresh() async {
        if case .loaded = state {} else { state = .loading }
        do {
            async let tickets = api.eusoTicket.listRunTickets(limit: 50)
            async let bols    = api.eusoTicket.listBOLs(limit: 50)
            let (tList, bList) = try await (tickets, bols)
            if tList.tickets.isEmpty && bList.bols.isEmpty {
                state = .empty
            } else {
                state = .loaded(tickets: tList.tickets, bols: bList.bols)
            }
        } catch {
            state = .error("Couldn't reach EusoTicket service.")
        }
    }

    /// Fire `eusoTicket.generateRunTicketPDF`. Returns an absolute URL
    /// the caller can hand to Safari, or nil on failure.
    func generateTicketPDF(ticketNumber: String) async -> URL? {
        mutatingId = "ticket::\(ticketNumber)"
        defer { mutatingId = nil }
        do {
            let res = try await api.eusoTicket.generateRunTicketPDF(
                ticketNumber: ticketNumber
            )
            flashToast(res.success ? "Run ticket PDF ready" : "PDF generation failed")
            return resolveDocumentURL(res.documentUrl)
        } catch {
            flashToast("PDF generation failed")
            return nil
        }
    }

    func generateBOLPDF(bolNumber: String) async -> URL? {
        mutatingId = "bol::\(bolNumber)"
        defer { mutatingId = nil }
        do {
            let res = try await api.eusoTicket.generateBOLPDF(
                bolNumber: bolNumber
            )
            flashToast(res.success ? "BOL PDF ready" : "PDF generation failed")
            return resolveDocumentURL(res.documentUrl)
        } catch {
            flashToast("PDF generation failed")
            return nil
        }
    }

    /// Server returns paths like `/documents/run-tickets/RT-123.pdf`.
    /// Resolve relative to the API origin so a tap opens correctly in
    /// SFSafariViewController. `EusoTripAPI.shared.baseURL` is the
    /// canonical origin used everywhere else for document fetches.
    private func resolveDocumentURL(_ raw: String) -> URL? {
        if let absolute = URL(string: raw), absolute.scheme != nil { return absolute }
        guard let origin = EusoTripAPI.shared.baseURL else { return nil }
        let originString = origin.absoluteString
        let trimmed = originString.hasSuffix("/")
            ? String(originString.dropLast())
            : originString
        return URL(string: trimmed + (raw.hasPrefix("/") ? raw : "/\(raw)"))
    }

    private func flashToast(_ text: String) {
        lastToast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { self.lastToast = nil }
        }
    }
}

// MARK: - Screen root

struct MeEusoTicketsView: View {
    @Environment(\.palette) var palette
    @StateObject private var store = EusoTicketsStore()
    @State private var section: EusoTicketsStore.Section = .tickets
    @State private var pdfURL: URL?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                sectionPicker
                content
                disclosure
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: Binding(
            get: { pdfURL.map { IdentifiedURL(url: $0) } },
            set: { pdfURL = $0?.url }
        )) { ident in
            #if canImport(UIKit)
            SafariView(url: ident.url)
                .ignoresSafeArea()
            #endif
        }
        .overlay(alignment: .bottom) {
            if let toast = store.lastToast {
                Text(toast)
                    .font(EType.caption)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .background(palette.bgCard.opacity(0.95))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .padding(.bottom, Space.s6)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.lastToast)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("EusoTicket")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("BOL · run ticket · haul receipts")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.mutatingId != nil ? .thinking : .idle, diameter: 40)
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: Space.s2) {
            ForEach(EusoTicketsStore.Section.allCases) { s in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { section = s }
                } label: {
                    Text(s.label)
                        .font(EType.bodyStrong)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, Space.s2)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(section == s
                                      ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                                      : AnyShapeStyle(palette.bgCard))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(section == s
                                              ? palette.borderSoft
                                              : palette.borderFaint,
                                              lineWidth: 1)
                        )
                        .foregroundStyle(section == s ? palette.textPrimary : palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            skeleton
        case .empty:
            emptyHero
        case .error(let msg):
            errorBanner(msg)
        case .loaded(let tickets, let bols):
            switch section {
            case .tickets:
                if tickets.isEmpty {
                    EusoEmptyState(
                        systemImage: "ticket",
                        title: "No run tickets yet",
                        subtitle: "When loads originate from a terminal that mints run tickets, they'll show up here.",
                        comingSoon: false
                    )
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(tickets) { row in ticketRow(row) }
                    }
                }
            case .bols:
                if bols.isEmpty {
                    EusoEmptyState(
                        systemImage: "doc.text",
                        title: "No Bills of Lading yet",
                        subtitle: "Once a load is BOL-issued, the document lands here. Pull-to-refresh after a terminal hands you a new BOL.",
                        comingSoon: false
                    )
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(bols) { row in bolRow(row) }
                    }
                }
            }
        }
    }

    // MARK: Rows

    private func ticketRow(_ t: EusoTicketAPI.RunTicketRow) -> some View {
        let mutating = store.mutatingId == "ticket::\(t.ticketNumber)"
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    Text(t.ticketNumber)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if t.spectraMatchVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .accessibilityLabel("SpectraMatch verified")
                    }
                }
                if let p = t.productName, !p.isEmpty {
                    Text(p)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let v = t.netVolume, v > 0 {
                        Text("\(Int(v)) bbl")
                            .font(EType.micro).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                    }
                    if let api = t.apiGravity, api > 0 {
                        Text("API \(String(format: "%.1f", api))")
                            .font(EType.micro).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                    }
                    if let term = t.terminalName, !term.isEmpty {
                        Text(term)
                            .font(EType.micro).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Text(t.status.uppercased())
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(statusTint(t.status))
            }
            Spacer(minLength: Space.s2)
            pdfChip(busy: mutating) {
                Task {
                    if let url = await store.generateTicketPDF(ticketNumber: t.ticketNumber) {
                        pdfURL = url
                    }
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func bolRow(_ b: EusoTicketAPI.BOLRow) -> some View {
        let mutating = store.mutatingId == "bol::\(b.bolNumber ?? "")"
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(b.bolNumber ?? "—")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                if let load = b.loadNumber, !load.isEmpty {
                    Text("Load \(load)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                if let driver = b.driverName, !driver.isEmpty {
                    Text(driver)
                        .font(EType.micro).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
                Text(b.status.uppercased())
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(statusTint(b.status))
            }
            Spacer(minLength: Space.s2)
            // If the BOL already has a fileUrl, jump straight to it;
            // otherwise mint a fresh PDF on demand.
            pdfChip(busy: mutating) {
                if let raw = b.fileUrl, let abs = URL(string: raw), abs.scheme != nil {
                    pdfURL = abs
                } else if let bol = b.bolNumber {
                    Task {
                        if let url = await store.generateBOLPDF(bolNumber: bol) {
                            pdfURL = url
                        }
                    }
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func pdfChip(busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if busy {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text("PDF")
                    .font(EType.micro).tracking(0.6).fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(LinearGradient.diagonal)
            )
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("Generate PDF")
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 76)
            }
        }
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "ticket",
            title: "Nothing on the haul yet",
            subtitle: "Run tickets and BOLs land here as terminals issue them. Pull to refresh.",
            comingSoon: false
        )
    }

    private func errorBanner(_ msg: String) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't load EusoTicket")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refresh() }
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

    private var disclosure: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "sparkles")
                .foregroundStyle(LinearGradient.diagonal)
            Text("Receipts (lumper · scale · fuel · toll) ride under Documents Center → Per-load section.")
                .font(EType.micro).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.top, Space.s2)
    }

    private func statusTint(_ status: String) -> Color {
        switch status.lowercased() {
        case "completed", "delivered":          return Brand.success
        case "in_transit", "active":            return Brand.info
        case "issued", "pending":               return Brand.warning
        case "cancelled":                       return Brand.danger
        default:                                return palette.textTertiary
        }
    }
}

// MARK: - Helpers

/// Identifiable URL wrapper so `.sheet(item:)` accepts a raw URL state.
private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

#if canImport(UIKit)
private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
#endif

// MARK: - Screen wrapper (registered in ContentView ScreenRegistry)
//
// Mirrors the `MeRateSheetScreen` / `MeAuthorityScreen` (104/105) shape:
// thin Shell wrapper that injects the palette and renders the Driver
// bottom-nav with "Me" highlighted. The DriverMePane sheet path uses the
// raw `MeEusoTicketsView` body inside `MeDetailContainer`; this wrapper
// is the dev-chrome entry point for the screen registry only — both
// surfaces share the same view body.

struct MeEusoTicketsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeEusoTicketsView()
        } nav: {
            BottomNav(
                leading: driverNavLeading_106(),
                trailing: driverNavTrailing_106(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_106() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_106() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("106 · Me · EusoTicket · Night") {
    MeEusoTicketsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("106 · Me · EusoTicket · Afternoon") {
    MeEusoTicketsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
