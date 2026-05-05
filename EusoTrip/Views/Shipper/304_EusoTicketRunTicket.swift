//
//  304_EusoTicketRunTicket.swift
//  EusoTrip — Shipper · EusoTicket · Run ticket (Arc H).
//
//  PDF download wires through `eusoTicket.generateRunTicketPDF` →
//  branded EusoTrip PDF generator (gradient header, QR code,
//  driver/carrier lockup, financials, 5-year retention banner).
//  Returns base64-encoded body iOS writes to a tmp file and
//  presents via `UIActivityViewController` so the founder + their
//  customers can Save to Files / AirDrop / Mail / Messages the
//  receipt. Replaces the 404 PDF download the founder reported
//  2026-05-05.
//

import SwiftUI

struct EusoTicketRunTicketScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { RunTicketBody(loadId: loadId) } nav: { shipperLifecycleNav() }
    }
}

private struct RunTicketDetail: Decodable, Hashable {
    let id: Int
    let pdfUrl: String?
    let status: String?
    let legCount: Int?
    let totalMiles: Double?
}

private struct RunTicketBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    @State private var ticket: RunTicketDetail? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    /// Drives `UIActivityViewController` after the PDF generator
    /// returns a base64 blob and we've staged it to a tmp file.
    @State private var pendingShareItems: [URL]? = nil
    @State private var pdfInflight: Bool = false
    @State private var pdfError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let t = ticket { card(t); ctaRow(t) }
                else if loading { LifecycleCard { Text("Generating run ticket…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .sheet(isPresented: Binding(
            get: { pendingShareItems != nil },
            set: { if !$0 { pendingShareItems = nil } }
        )) {
            if let urls = pendingShareItems {
                EusoTicketShareSheet(items: urls)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) {
            if let err = pdfError {
                Text(err)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.red.opacity(0.92), in: Capsule())
                    .padding(.top, 12)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            await MainActor.run { pdfError = nil }
                        }
                    }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "ticket").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("EUSOTICKET · RUN TICKET").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Run ticket").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func card(_ t: RunTicketDetail) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "DETAILS", icon: "doc.text")
            LifecycleRow(label: "Ticket ID",  value: "RT-\(t.id)")
            LifecycleRow(label: "Status",     value: dashIfEmpty(t.status?.uppercased()))
            LifecycleRow(label: "Legs",       value: t.legCount.map { "\($0)" } ?? "—")
            LifecycleRow(label: "Total miles", value: t.totalMiles.map { "\(Int($0)) mi" } ?? "—")
        }
    }

    /// Real PDF download — calls `eusoTicket.generateRunTicketPDF`,
    /// decodes the base64 body, writes to a tmp file, and presents
    /// the system Share sheet.
    private func ctaRow(_ t: RunTicketDetail) -> some View {
        Button {
            Task { await downloadPDF(t) }
        } label: {
            HStack(spacing: 8) {
                if pdfInflight {
                    ProgressView().progressViewStyle(.circular).tint(.white).controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 13, weight: .heavy))
                }
                Text(pdfInflight ? "Generating PDF…" : "Download PDF")
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(pdfInflight)
    }

    private func downloadPDF(_ t: RunTicketDetail) async {
        guard !pdfInflight else { return }
        pdfInflight = true
        defer { Task { @MainActor in pdfInflight = false } }
        struct In: Encodable { let ticketNumber: String }
        struct Out: Decodable { let filename: String; let mime: String; let body: String; let universalLink: String? }
        let ticketNumber = "RT-\(t.id)"
        do {
            let resp: Out = try await EusoTripAPI.shared.query(
                "eusoTicket.generateRunTicketPDF",
                input: In(ticketNumber: ticketNumber)
            )
            guard let pdf = Data(base64Encoded: resp.body), !pdf.isEmpty else {
                await MainActor.run { pdfError = "PDF body empty" }
                return
            }
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("eusotrip-tickets", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(resp.filename)
            try pdf.write(to: url, options: .atomic)
            await MainActor.run { pendingShareItems = [url] }
        } catch {
            let msg = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            await MainActor.run { pdfError = "PDF failed: \(msg)" }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let loadId: Int }
        let n = Int(loadId.replacingOccurrences(of: "load_", with: "")) ?? 0
        do {
            let t: RunTicketDetail = try await EusoTripAPI.shared.mutation("eusoTicket.generateRunTicket", input: In(loadId: n))
            ticket = t
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

private struct EusoTicketShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview("304 · Run ticket · Night") {
    EusoTicketRunTicketScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("304 · Run ticket · Afternoon") {
    EusoTicketRunTicketScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
