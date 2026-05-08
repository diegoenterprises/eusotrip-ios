//
//  297_MonthlyStatement.swift
//  EusoTrip — Shipper · Monthly statement (Arc G).
//  Backed by `earnings.getPayStatement` (existing).
//

import SwiftUI

struct MonthlyStatementScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { MonthlyStatementBody() } nav: { shipperLifecycleNav() }
    }
}

private struct PayStatement: Decodable, Hashable {
    let period: String?
    let totalEarnings: Double?
    let deductions: Double?
    let netPay: Double?
    let pdfUrl: String?
    let lineItems: [LineItem]?
    struct LineItem: Decodable, Hashable, Identifiable {
        let id: String
        let label: String
        let amount: Double
    }
}

private struct MonthlyStatementBody: View {
    @Environment(\.palette) private var palette
    @State private var statement: PayStatement? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var presentedPDF: EusoPDFPresentation? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = statement { totalsHero(s); lineItemsCard(s); pdfCard(s) }
                else if loading { LifecycleCard { Text("Loading statement…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .fullScreenCover(item: $presentedPDF) { p in
            EusoPDFViewer(title: p.title, subtitle: p.subtitle, source: .url(p.url))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · STATEMENT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(statement?.period ?? "Monthly statement").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func totalsHero(_ s: PayStatement) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "TOTALS", icon: "creditcard")
            LifecycleRow(label: "Total earnings", value: usd(s.totalEarnings))
            LifecycleRow(label: "Deductions",     value: usd(s.deductions))
            LifecycleRow(label: "Net pay",        value: usd(s.netPay))
        }
    }

    private func lineItemsCard(_ s: PayStatement) -> some View {
        LifecycleCard {
            LifecycleSection(label: "LINE ITEMS", icon: "list.bullet")
            if let items = s.lineItems, !items.isEmpty {
                ForEach(items) { LifecycleRow(label: $0.label, value: usd($0.amount)) }
            } else {
                Text("Line items not yet broken out for this period.").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func pdfCard(_ s: PayStatement) -> some View {
        if let u = s.pdfUrl, !u.isEmpty {
            return AnyView(Button {
                if let url = URL(string: u) {
                    presentedPDF = EusoPDFPresentation(
                        url: url,
                        title: "Monthly statement",
                        subtitle: s.period
                    )
                }
            } label: {
                Text("Open statement PDF").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain))
        }
        return AnyView(EmptyView())
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let s: PayStatement = try await EusoTripAPI.shared.queryNoInput("earnings.getPayStatement")
            statement = s
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("297 · Statement · Night") {
    MonthlyStatementScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("297 · Statement · Afternoon") {
    MonthlyStatementScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
