import Foundation

@main
struct NewsArticleURLVerifier {
    private static func article(link: String) -> NewsArticle {
        NewsArticle(
            id: "article-url-verifier",
            title: "Article URL verifier",
            summary: "Publisher supplied summary.",
            link: link,
            publishedAt: "2026-08-23T00:00:00.000Z",
            source: "Verifier",
            sourceUrl: "https://example.com/rss",
            category: "logistics",
            imageUrl: nil
        )
    }

    private static func expect(_ raw: String, toResolveTo expected: String) {
        let actual = article(link: raw).articleURL?.absoluteString
        precondition(actual == expected, "Expected \(raw) to resolve to \(expected), got \(actual ?? "nil")")
    }

    private static func reject(_ raw: String) {
        precondition(article(link: raw).articleURL == nil, "Expected \(raw) to be rejected")
    }

    static func main() {
        let reportedURL = "https://www.dcvelocity.com/editorial/featured/cobot-shipments-to-rise-more-than-17-by-2030-china-maintains-market-dominance"
        expect(reportedURL, toResolveTo: reportedURL)
        expect("  \n\(reportedURL)\t", toResolveTo: reportedURL)
        expect(
            "HTTPS://example.com/article?first=1&amp;second=2",
            toResolveTo: "https://example.com/article?first=1&second=2"
        )

        reject("")
        reject("/relative/article")
        reject("javascript:alert(1)")
        reject("mailto:editor@example.com")
        reject("file:///tmp/article.html")
        reject("https:///missing-host")
        reject("https://reader:secret@example.com/article")

        print("NewsArticle URL verifier passed")
    }
}
