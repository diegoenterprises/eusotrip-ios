//
//  347_HelpSupport.swift
//  EusoTrip — Shipper · Help & support (Arc K).
//

import SwiftUI

struct HelpSupportScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { HelpSupportBody() } nav: { shipperLifecycleNav() }
    }
}

private struct HelpArticle: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let category: String?
    let summary: String?
    /// Optional markdown / plain-text body. The current server-side
    /// help stub doesn't ship article bodies yet (the table isn't
    /// built); the reader gracefully falls back to summary when
    /// body is missing.
    let body: String?
}

private struct HelpSupportBody: View {
    @Environment(\.palette) private var palette
    @State private var query: String = ""
    @State private var articles: [HelpArticle] = []
    @State private var loading = true
    /// In-app article reader sheet. Replaces the previous
    /// `UIApplication.shared.open(https://eusotrip.com/help/...)`
    /// Safari punt with a native SwiftUI sheet so the user never
    /// leaves the app to read a help article.
    @State private var openedArticle: HelpArticle? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                searchBar
                quickContact
                articlesCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .sheet(item: $openedArticle) { article in
            HelpArticleReaderSheet(article: article)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · HELP & SUPPORT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Help & support").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var searchBar: some View {
        TextField("Search help", text: $query)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onSubmit { Task { await load() } }
    }

    private var quickContact: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "DIRECT CONTACT", icon: "phone")
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "318"])
            } label: {
                HStack {
                    Image(systemName: "phone.arrow.up.right").foregroundStyle(.white)
                    Text("Escalate to dispatch").font(EType.bodyStrong).foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }.buttonStyle(.plain)
            Button { if let u = URL(string: "mailto:support@eusotrip.com") { UIApplication.shared.open(u) } } label: {
                HStack {
                    Image(systemName: "envelope").foregroundStyle(LinearGradient.diagonal)
                    Text("Email support@eusotrip.com").font(EType.body).foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                }
            }.buttonStyle(.plain)
        }
    }

    private var articlesCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ARTICLES", icon: "book")
            if loading {
                Text("Loading articles…").font(EType.caption).foregroundStyle(palette.textSecondary)
            } else if articles.isEmpty {
                Text("No matching articles.").font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                ForEach(articles) { a in
                    Button {
                        openedArticle = a
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                            Text(dashIfEmpty(a.summary)).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func load() async {
        loading = true
        // Server endpoint is `help.getArticles`. Earlier code called
        // a non-existent `help.search` which always errored, so the
        // articles list stayed permanently empty. Real endpoint
        // returns `[]` until the help_articles table ships, but at
        // least we no longer drop the request on the floor.
        struct In: Encodable { let categoryId: String?; let search: String? }
        do {
            let r: [HelpArticle] = try await EusoTripAPI.shared.query(
                "help.getArticles",
                input: In(categoryId: nil, search: query.isEmpty ? nil : query)
            )
            articles = r
        } catch { articles = [] }
        loading = false
    }
}

// MARK: - In-app article reader sheet

private struct HelpArticleReaderSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let article: HelpArticle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text((article.category ?? "HELP").uppercased())
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Text(article.title)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let summary = article.summary, !summary.isEmpty {
                        Text(summary)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider().background(palette.borderFaint)
                    if let body = article.body, !body.isEmpty {
                        Text(body)
                            .font(EType.body)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Full article body not available yet.")
                                .font(EType.body)
                                .foregroundStyle(palette.textPrimary)
                            Text("Email support@eusotrip.com or tap Escalate to dispatch from the previous screen — a human responds the same business day.")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(palette.bgPage)
            .navigationTitle("Help article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
        }
    }
}

#Preview("347 · Help · Night") { HelpSupportScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("347 · Help · Afternoon") { HelpSupportScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
