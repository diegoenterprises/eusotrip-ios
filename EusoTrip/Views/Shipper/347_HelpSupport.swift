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
}

private struct HelpSupportBody: View {
    @Environment(\.palette) private var palette
    @State private var query: String = ""
    @State private var articles: [HelpArticle] = []
    @State private var loading = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                searchBar
                quickContact
                articlesCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
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
                        if let u = URL(string: "https://eusotrip.com/help/\(a.id)") { UIApplication.shared.open(u) }
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
        struct In: Encodable { let q: String? }
        do {
            let r: [HelpArticle] = try await EusoTripAPI.shared.query("help.search", input: In(q: query.isEmpty ? nil : query))
            articles = r
        } catch { articles = [] }
        loading = false
    }
}

#Preview("347 · Help · Night") { HelpSupportScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("347 · Help · Afternoon") { HelpSupportScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
