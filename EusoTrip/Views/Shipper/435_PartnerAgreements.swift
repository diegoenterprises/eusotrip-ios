//
//  435_PartnerAgreements.swift
//  EusoTrip — Shipper · Partner agreements list (deepens 223).
//
//  Cross-role chain: shipper signing an agreement here → carrier-side
//  catalysts.getMyPendingAgreements surfaces the inbound request →
//  catalysts.signAgreement closes the loop. Agreements router on the
//  server already broadcasts AGREEMENT_SIGNED.
//

import SwiftUI

struct PartnerAgreementsScreen: View {
    let theme: Theme.Palette
    let partnerId: String
    var body: some View {
        Shell(theme: theme) { PartnerAgreementsBody(partnerId: partnerId) } nav: { shipperLifecycleNav() }
    }
}

private struct AgreementRow: Decodable, Identifiable, Hashable {
    let id: String
    let agreementNumber: String
    let kind: String
    let status: String
    let signedAt: String?
    let pdfUrl: String?
}

private struct PartnerAgreementsBody: View {
    @Environment(\.palette) private var palette
    let partnerId: String
    @State private var rows: [AgreementRow] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var signing: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.append").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · PARTNER AGREEMENTS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Agreements").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading agreements…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty { EusoEmptyState(systemImage: "doc.append", title: "No agreements", subtitle: "Author one from the agreements wizard at /agreements.") }
        else {
            ForEach(rows) { a in
                LifecycleCard(accentGradient: a.status == "signed") {
                    LifecycleSection(label: a.agreementNumber.uppercased(), icon: "doc.text")
                    LifecycleRow(label: "Kind",     value: a.kind.uppercased())
                    LifecycleRow(label: "Status",   value: a.status.uppercased())
                    LifecycleRow(label: "Signed",   value: humanISO(a.signedAt))
                    HStack(spacing: 8) {
                        if let pdf = a.pdfUrl, !pdf.isEmpty {
                            Button { if let u = URL(string: pdf) { UIApplication.shared.open(u) } } label: {
                                Text("PDF").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(palette.tintNeutral).clipShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                        if a.status == "pending_shipper" {
                            Button { Task { await sign(a.id) } } label: {
                                HStack { if signing == a.id { ProgressView().tint(.white) }
                                    Text(signing == a.id ? "Signing…" : "Sign").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white) }
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(LinearGradient.diagonal).clipShape(Capsule())
                            }.buttonStyle(.plain).disabled(signing != nil)
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let partnerId: String }
        do {
            let r: [AgreementRow] = try await EusoTripAPI.shared.api.query("agreements.listForPartner", input: In(partnerId: partnerId))
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func sign(_ id: String) async {
        signing = id
        struct In: Encodable { let agreementId: String }
        struct Out: Decodable { let success: Bool }
        let _ : Out = (try? await EusoTripAPI.shared.api.mutation("agreements.sign", input: In(agreementId: id))) ?? Out(success: false)
        await load()
        signing = nil
    }
}

#Preview("435 · Agreements · Night") { PartnerAgreementsScreen(theme: Theme.dark, partnerId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("435 · Agreements · Afternoon") { PartnerAgreementsScreen(theme: Theme.light, partnerId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
