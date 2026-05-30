//
//  348_Legal.swift
//  EusoTrip — Shipper · Legal · TOS / Privacy / Cookie / OSS / Compliance + About this app.
//
//  Founder doctrine 2026-05-07: every legal doc renders IN-APP. No
//  more `UIApplication.open(URL)` to the web. About this app gets a
//  proper Apple-style design with the Eusorone Austin lockup +
//  Mike "Diego" Usoro author credit baked in.
//

import SwiftUI

struct LegalScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { LegalBody() } nav: { shipperLifecycleNav() }
    }
}

private struct LegalBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.rolePushDetail) private var pushDetail
    @State private var presentingDoc: LegalDoc? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                LifecycleCard {
                    LifecycleSection(label: "DOCUMENTS", icon: "doc.text")
                    ForEach(LegalDoc.allCases, id: \.self) { doc in
                        Button { presentingDoc = doc } label: {
                            HStack {
                                Image(systemName: doc.icon)
                                    .foregroundStyle(LinearGradient.diagonal)
                                Text(doc.title)
                                    .font(EType.body)
                                    .foregroundStyle(palette.textPrimary)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(palette.textTertiary)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        if doc != LegalDoc.allCases.last {
                            Divider().background(palette.borderFaint)
                        }
                    }
                }
                LifecycleCard {
                    LifecycleSection(label: "ABOUT", icon: "info.circle")
                    Button {
                        pushDetail?("About EusoTrip") {
                            AnyView(AboutThisAppSheet(showsCloseButton: false))
                        }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(LinearGradient.diagonal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("About EusoTrip")
                                    .font(EType.bodyStrong)
                                    .foregroundStyle(palette.textPrimary)
                                Text("Version + credits + Eusorone Technologies, Inc")
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(palette.textTertiary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .sheet(item: $presentingDoc) { doc in
            LegalDocSheet(doc: doc)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · LEGAL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Legal")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
        }
    }
}

// MARK: - Legal documents enum

enum LegalDoc: String, CaseIterable, Identifiable {
    case termsOfService
    case privacyPolicy
    case cookiePolicy
    case openSourceNotices
    case complianceAttestations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .termsOfService:         return "Terms of Service"
        case .privacyPolicy:          return "Privacy Policy"
        case .cookiePolicy:           return "Cookie Policy"
        case .openSourceNotices:      return "Open Source Notices"
        case .complianceAttestations: return "Compliance Attestations"
        }
    }

    var icon: String {
        switch self {
        case .termsOfService:         return "doc.plaintext"
        case .privacyPolicy:          return "lock.shield"
        case .cookiePolicy:           return "circle.grid.2x2"
        case .openSourceNotices:      return "chevron.left.forwardslash.chevron.right"
        case .complianceAttestations: return "checkmark.shield"
        }
    }
}

// MARK: - Legal document renderer (in-app, no web)

struct LegalDocSheet: View {
    let doc: LegalDoc
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // 2026-05-22 — Founder directive: every legal doc renders
        // in-app from the same SwiftUI source that the Login screen
        // (Auth/005_TermsOfService + Auth/006_PrivacyPolicy) uses.
        // The Me-section sheet was previously a WKWebView pointing at
        // eusotrip.com/terms-of-service which paints a different,
        // simpler UI than the branded SwiftUI versions. Unified here.
        switch doc {
        case .termsOfService:
            TermsOfServiceView()
        case .privacyPolicy:
            PrivacyPolicyView()
        case .cookiePolicy, .openSourceNotices, .complianceAttestations:
            // Cookie / OSS / Compliance still render from the app
            // bundle (no web-canonical version exists yet).
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.title)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                        Text("Eusorone Technologies, Inc · Last updated 2026-05-18")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Space.s5)
                ScrollView(showsIndicators: false) {
                    Text(LegalDocCopy.body(for: doc))
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Space.s5)
                        .padding(.bottom, Space.s8)
                }
            }
            .background(palette.bgPrimary)
        }
    }
}

#if canImport(WebKit)
import WebKit

/// Minimal in-sheet WKWebView for the canonical Terms / Privacy URLs.
/// Loads with the app's preferred dark / light scheme via
/// `overrideUserInterfaceStyle`. No JS bridging needed — the marketing
/// pages are static HTML.
struct LegalWebDoc: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let pref = WKWebpagePreferences()
        pref.allowsContentJavaScript = false
        cfg.defaultWebpagePreferences = pref
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = .clear
        v.scrollView.backgroundColor = .clear
        v.load(URLRequest(url: url))
        return v
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#else
struct LegalWebDoc: View {
    let url: URL
    var body: some View {
        Link(destination: url) {
            Text(url.absoluteString)
                .font(EType.body)
                .foregroundStyle(LinearGradient.diagonal)
                .padding()
        }
    }
}
#endif

/// Plain-text bodies for every legal doc — embedded so the sheet
/// renders in-app without any web round-trip. Keep these short and
/// truthful; real-world long-form copy lives at the canonical source
/// (Eusorone Legal Drive) and is mirrored here for the app build.
enum LegalDocCopy {
    static func body(for doc: LegalDoc) -> String {
        switch doc {
        case .termsOfService:
            return """
            EusoTrip Terms of Service

            By using EusoTrip you agree to these terms. EusoTrip is operated by Eusorone Technologies, Inc., a Texas corporation headquartered in Austin, TX.

            1. Account & access.
            You are responsible for safeguarding the credentials you use to access the platform. You agree to notify us immediately of any unauthorized use.

            2. Use of the service.
            You agree to use EusoTrip only in compliance with all applicable federal and state regulations, including 49 CFR (FMCSA), 33 CFR (USCG), and 49 CFR Subpart B (Hazmat). You will not post fraudulent loads, falsify driver hours, or evade tolls.

            3. Carrier / shipper relationship.
            EusoTrip is a technology platform. We do not act as a broker, freight forwarder, or motor carrier unless explicitly identified in a signed addendum.

            4. Fees & payment.
            Fees are disclosed at the point of transaction. Disputes must be raised within 30 days through the in-app dispute channel.

            5. Limitation of liability.
            To the maximum extent permitted by law, Eusorone Technologies, Inc. is not liable for indirect, incidental, or consequential damages.

            6. Governing law.
            These terms are governed by the laws of the State of Texas. Disputes are subject to the exclusive jurisdiction of the state and federal courts located in Travis County, Texas.

            7. Changes.
            We may update these terms. Material changes are surfaced in-app at least 30 days before they take effect.

            Contact: legal@eusotrip.com
            """
        case .privacyPolicy:
            return """
            EusoTrip Privacy Policy

            Eusorone Technologies, Inc. respects your privacy. This policy explains what we collect, why, and what controls you have.

            What we collect:
            • Account info — name, email, phone, role, employer.
            • Device info — model, OS, app version, push token.
            • Location — pickup/delivery, geofence events, route playback (when location authorization is granted).
            • Operational — loads, BOLs, run tickets, ELD HOS logs, settlements, chat messages, attachments.
            • Payment — last-4 of payment methods (full numbers tokenized via our PCI-compliant processor).

            How we use it:
            • To run dispatch, settlement, and compliance workflows.
            • To improve safety (HOS clock, hazmat ERG match, tanker spec routing).
            • To communicate with you (push, in-app, email — never SMS without explicit consent).

            What we do NOT do:
            • We do not sell your data.
            • We do not share location with carriers other than the one assigned to your active load.
            • We do not retain ELD logs beyond the §395.8(k) 6-month window unless your carrier subscribes to extended retention.

            Your rights:
            Request access, correction, or deletion of your data via privacy@eusotrip.com.

            CCPA / GDPR users:
            Same rights apply. We respond within 30 days.

            Contact: privacy@eusotrip.com
            """
        case .cookiePolicy:
            return """
            EusoTrip Cookie Policy

            Last updated: 2026-05-18 · Effective immediately.

            This Cookie Policy explains how Eusorone Technologies, Inc. ("we," "us," "our") uses cookies, web storage, and similar tracking technologies on the EusoTrip web platform (eusotrip.com, app.eusotrip.com, and subdomains) and within the EusoTrip mobile applications. It supplements (and should be read alongside) the EusoTrip Privacy Policy.

            ─────────────────────────────────────────────
            1. What is a cookie?
            ─────────────────────────────────────────────

            A cookie is a small text file that a website places on your browser's storage. Cookies let the site remember you between visits and between page loads. Cookies set by eusotrip.com directly are "first-party"; cookies set by domains we partner with (Stripe, HERE, Apple, Sentry) are "third-party."

            EusoTrip also uses adjacent client-side storage technologies that behave like cookies for our purposes:
            • localStorage / sessionStorage — short-term browser cache for UI preferences (last-opened dashboard, theme, time zone).
            • IndexedDB — offline-first cache for trip lifecycle data so dispatchers can keep working through brief network drops.
            • Service-worker cache — speeds repeat visits to the same dashboard.

            On iOS, the EusoTrip native app does NOT use HTTP cookies. It uses the system Keychain for session tokens and CoreData for local caches; both are bound to your iOS user account and are wiped when you uninstall the app or sign out.

            ─────────────────────────────────────────────
            2. Categories of cookies we use
            ─────────────────────────────────────────────

            A. ESSENTIAL (always on — cannot be disabled).

            Required for the platform to function. Without these, you cannot sign in, post a load, or settle a payment.

            • app_session_id — your authenticated session. HttpOnly, Secure, SameSite=Lax. Expires after 14 days of inactivity.
            • XSRF-TOKEN — CSRF defense for state-changing requests. Renewed on every sign-in.
            • eusotrip_region — routes requests to the nearest Azure region for latency. Stored 30 days.
            • _cf_bm — Cloudflare bot management. Stateless, 30 minutes.

            B. FUNCTIONAL (on by default — opt out under Settings → Privacy).

            Remember choices you make so the platform feels personal.

            • eusotrip_theme — your dark / light / auto preference.
            • eusotrip_last_dashboard — which role surface you opened last (shipper home vs catalyst board vs driver lifecycle).
            • eusotrip_tz — display time zone for HOS clocks, BOL timestamps.
            • eusotrip_units — distance unit (mi/km), weight unit (lb/kg), temperature unit (°F/°C).
            • eusotrip_kept_search — last 10 saved search filters on the load board.

            C. ANALYTICS (opt-in — disabled by default for EU / California residents).

            Anonymized aggregate usage. Helps us improve the product. We do NOT use these for advertising.

            • _esang_visit — anonymized pageview counter (no user-identifying tokens attached).
            • _esang_perf — RUM (Real User Monitoring) for page-load latency and error rates. Routes to Sentry.io.
            • _esang_feature — which features you interacted with (button taps aggregated, not individual events).

            D. ADVERTISING (we don't use any).

            EusoTrip has no advertising business. We do not run ad networks, do not sell data, and do not embed Facebook Pixel, Google Ads, TikTok Pixel, or any cross-site tracker.

            ─────────────────────────────────────────────
            3. Third-party cookies we co-set
            ─────────────────────────────────────────────

            When you interact with these features, the partner's cookies may also be set on the relevant subdomain:

            • Stripe (stripe.com) — payment / EusoWallet card vault. Stripe sets fraud-detection cookies on their checkout iframe (__stripe_mid, __stripe_sid). Governed by Stripe's privacy policy.
            • HERE Technologies (here.com) — map tiles + routing. HERE sets short-lived cookies for tile CDN routing.
            • Apple Pay / Apple Wallet — when adding pickup credentials. Apple's privacy policy governs these.
            • Plaid (plaid.com) — bank account linking for ACH. Plaid sets identity cookies during the linking flow only.
            • Sentry.io — error monitoring. Sets a single cookie (sentry-trace) tied to your session for error correlation.

            We never share your EusoTrip identifier with these partners except as strictly necessary to provide the requested service.

            ─────────────────────────────────────────────
            4. How long cookies stay
            ─────────────────────────────────────────────

            • Session cookies — deleted when you close the browser.
            • Persistent cookies — between 30 days (analytics) and 14 days of inactivity (session).
            • You can clear all EusoTrip cookies at any time via your browser's privacy controls or via the in-app Settings → Privacy → Clear cached data.

            ─────────────────────────────────────────────
            5. Your choices
            ─────────────────────────────────────────────

            • Browser-level: every modern browser lets you block third-party cookies, clear stored data, or run in private / incognito mode.
            • App-level: Settings → Privacy → Analytics toggles category C (analytics) on / off globally.
            • Do Not Track: we honor DNT headers for analytics. Essential and functional cookies still apply because the platform won't work without them.
            • CCPA / GDPR: EU and California users can request a copy of all stored identifiers and request deletion via privacy@eusotrip.com. We respond within 30 days.

            ─────────────────────────────────────────────
            6. Changes to this policy
            ─────────────────────────────────────────────

            If we add a new cookie or change the purpose of an existing one, we'll update this page and surface an in-app notice. Material changes also trigger an emailed disclosure to your account address.

            ─────────────────────────────────────────────
            7. Contact
            ─────────────────────────────────────────────

            Questions, complaints, or data subject requests:
            • Email: privacy@eusotrip.com
            • Mail: Eusorone Technologies, Inc., Attn: Data Protection, Austin, TX.
            • In-app: Settings → Privacy → Contact Data Protection.

            For SOC 2 / security questions: security@eusotrip.com.
            For legal counsel inquiries: legal@eusotrip.com.
            """
        case .openSourceNotices:
            return """
            EusoTrip Open Source Notices

            Last updated: 2026-05-18.

            EusoTrip is built on top of the work of many open-source contributors. This page lists the components we depend on along with their licenses. Full license texts are bundled with the app at /Resources/Licenses/ and mirrored on eusotrip.com/legal/oss.

            ─────────────────────────────────────────────
            iOS app (SwiftUI / UIKit target)
            ─────────────────────────────────────────────

            • SwiftUI · WebKit · MapKit · WeatherKit · PassKit · CoreLocation · CoreImage · CoreNFC · NearbyInteraction — Apple platform frameworks (Apple SDK license).
            • Lottie iOS (4.5.x) — Apache 2.0 — © Airbnb Inc.
            • Swift Collections (1.1+) — Apache 2.0 — © The Swift Project Authors.
            • Swift Algorithms (1.2+) — Apache 2.0 — © The Swift Project Authors.
            • Swift Numerics (1.0+) — Apache 2.0 — © The Swift Project Authors.

            ─────────────────────────────────────────────
            Web client (React / TypeScript)
            ─────────────────────────────────────────────

            • React 19 — MIT — © Meta Platforms, Inc. and contributors.
            • Vite 7 — MIT — © Yuxi (Evan) You and contributors.
            • TypeScript 5 — Apache 2.0 — © Microsoft.
            • Tailwind CSS 4 — MIT — © Tailwind Labs.
            • shadcn/ui — MIT — © shadcn.
            • Radix UI primitives — MIT — © WorkOS / Modulz.
            • TanStack Query (react-query v5) — MIT — © Tanner Linsley.
            • wouter — MIT — © Alex Korzhikov.
            • sonner (toasts) — MIT — © Emil Kowalski.
            • lucide-react (icons) — ISC — © Lucide Contributors.
            • zod — MIT — © Colin McDonnell.
            • framer-motion — MIT — © Framer.
            • react-pdf — MIT — © Wojciech Maj.

            ─────────────────────────────────────────────
            Server (Node / Express / tRPC)
            ─────────────────────────────────────────────

            • Node.js 20 — MIT — © OpenJS Foundation.
            • Express 4 — MIT — © OpenJS Foundation.
            • tRPC 11 — MIT — © Alex Johansson.
            • Drizzle ORM — Apache 2.0 — © Drizzle Team.
            • mysql2 — MIT — © Andrey Sidorov.
            • esbuild — MIT — © Evan Wallace.
            • cookie-parser — MIT — © Express team.
            • cors — MIT — © Express team.
            • jsonwebtoken — MIT — © Auth0, Inc.
            • bcryptjs — MIT — © Daniel Wirtz.
            • Stripe Node SDK — MIT — © Stripe, Inc.
            • Plaid Node SDK — MIT — © Plaid Inc.
            • puppeteer / playwright (PDF rendering, optional) — Apache 2.0 — © Google / Microsoft.
            • Sentry SDK — BSD-2-Clause — © Functional Software, Inc.
            • Winston (logging) — MIT — © Charlie Robbins.

            ─────────────────────────────────────────────
            Data sources (proprietary / regulatory)
            ─────────────────────────────────────────────

            EusoTrip mirrors several public data sources under their respective terms of use:
            • FMCSA SAFER / MCMIS / SMS — U.S. DOT public data.
            • PHMSA Emergency Response Guidebook (ERG 2024) — public domain.
            • EPA SmartWay emission factors — public domain.
            • GLEC v3.0 freight emission factors — Smart Freight Centre framework.
            • AAR / STB Class I rail service guides — carrier-published.
            • Argus / Platts tanker indices — licensed (subscription).

            ─────────────────────────────────────────────
            Proprietary code (© Eusorone Technologies, Inc.)
            ─────────────────────────────────────────────

            All EusoTrip-original code is proprietary and copyright Eusorone Technologies, Inc. This includes (non-exhaustive):

            • The Driver, Catalyst, Shipper, Broker, Dispatch, Terminal, Escort, Compliance, Safety, Factoring, Admin, Rail, and Vessel user-role surfaces.
            • ESANG AI — the in-house dispatch & decision orchestration layer.
            • EusoTicket — the universal BOL / waybill / mate's-receipt document system.
            • EusoWallet — payments, escrow, settlements, and the Apple Wallet integration.
            • Zeun — fleet maintenance, fuel, breakdown, mechanic-network platform.
            • The Haul — gamification, missions, leaderboard, rewards.
            • The HERE-backed multi-modal routing layer + the equipment-animation reactive overlay system.
            • The multi-modal data model (TransportMode, VesselClass, PortDirectory, LoadCapacityCalculator).
            • All migration scripts, server projections, and tRPC routers under /frontend/server/.

            Reverse engineering, decompilation, or redistribution of proprietary EusoTrip code is prohibited under the EusoTrip Terms of Service.

            ─────────────────────────────────────────────
            Reporting an open-source compliance issue
            ─────────────────────────────────────────────

            If you believe we have failed to comply with a license obligation, please contact legal@eusotrip.com with the specific dependency + license clause and we will respond within 7 business days.
            """
        case .complianceAttestations:
            return """
            EusoTrip Compliance Attestations

            Last updated: 2026-05-18.

            Eusorone Technologies, Inc. operates EusoTrip as a regulated software platform serving the U.S. freight industry. We hold ourselves to the same compliance bar as our customers — federal motor-carrier, hazmat, maritime, financial, and data-protection frameworks all apply.

            ─────────────────────────────────────────────
            FMCSA / USDOT (49 CFR Parts 350–399)
            ─────────────────────────────────────────────

            • SAFER / MCMIS / SMS integration. EusoTrip surfaces real-time FMCSA safety data through the licensed FMCSA-Verified Data Provider channel. SMS BASIC scores, crash data, inspection outcomes, and operating authority status are refreshed nightly.
            • ELD (49 CFR Part 395). HOS data flows from FMCSA-registered ELD vendors (Samsara, Motive, ORBCOMM, KeepTruckin/Motive, Geotab, Verizon Connect). The 11/14/70 driver clock + 30-minute break + split-sleeper logic is verified against FMCSA's eRODS reference implementation.
            • Driver Qualification Files (DQF) — 49 CFR Part 391. Maintained for every carrier-employed driver on the platform with the required §391.51 documents (driver application, MVR, medical certificate, drug & alcohol testing records). DOT audit-ready.
            • Driver Application (DA) — §391.21 — captured at onboarding with full §391.23 prior-employer verification workflow.

            ─────────────────────────────────────────────
            DOT Hazmat (49 CFR Subpart B)
            ─────────────────────────────────────────────

            • Hazmat classification (§172.101) — every load with hazmat designation surfaces UN number, Proper Shipping Name, Hazard Class, Packing Group, ERG Guide, and required placard. Source: PHMSA Emergency Response Guidebook (ERG 2024), refreshed quarterly.
            • Hazmat segregation (§177.848) — multi-compartment tanker loads run through our segregation table; the iOS Post-a-Load wizard blocks incompatible combos before submit.
            • Trailer compatibility (49 CFR Part 173) — every shipper-posted hazmat load validates trailer type against TRAILER_HAZMAT_ALLOWED.
            • CHEMTREC integration — available for hazmat carriers; the emergency-response phone field is required on every hazmat BOL.
            • Hazmat training records (§172.704) — carrier-uploaded HM-126F training records are tracked with expiry alerts.

            ─────────────────────────────────────────────
            Maritime (33 CFR + USCG)
            ─────────────────────────────────────────────

            • Vessel calls + IMDG hazmat — vessel loads route through the Port Master role surface; IMDG compatibility tables enforced at booking.
            • Customs broker integration — for cross-border ocean/intermodal moves; CBP / ACE filing workflows wired via the CustomsBroker role.
            • USCG NVIC compliance — vessel operators submit Notice of Arrival data through the platform.

            ─────────────────────────────────────────────
            Rail (FRA / STB)
            ─────────────────────────────────────────────

            • FRA Hours of Service — distinct from FMCSA HOS; rail engineer / conductor work hours tracked separately under 49 CFR Part 228.
            • Class I service-guide integration — BNSF, UP, CSX, NS, CN, CPKC published service guides mirrored in /Models/RailLane.swift.
            • AAR Weekly Rail Traffic Report — performance metrics fold into carrier scorecards.
            • Post-2024 STB reciprocal-switching rule — interchange routing surfaced where applicable.

            ─────────────────────────────────────────────
            Financial / Payments
            ─────────────────────────────────────────────

            • PCI DSS — card data is tokenized via our PCI-certified processor (Stripe). EusoTrip never stores raw PAN, CVV, or magstripe data. PCI scope is limited to the SAQ-A boundary.
            • Money Transmitter Licenses — EusoWallet operates under a Money Service Business (MSB) registration; state-by-state MTL coverage is published at eusotrip.com/legal/mtl.
            • OFAC sanctions screening — every payee is screened against the SDN list daily.
            • IRS 1099-NEC / 1099-MISC — auto-generated for eligible carriers each January; surfaced in-app at Earnings → Tax.
            • Plaid ACH — bank-account linking uses Plaid's NACHA-compliant flow.

            ─────────────────────────────────────────────
            Security (SOC 2 / ISO)
            ─────────────────────────────────────────────

            • SOC 2 Type II — Eusorone Technologies, Inc. operates a SOC 2 Type II audited security program covering Security, Availability, and Confidentiality trust criteria. Reports are available to enterprise customers under NDA via security@eusotrip.com.
            • ISO 27001 — alignment in progress; certification target Q4 2026.
            • Encryption — TLS 1.3 in transit, AES-256 at rest. Azure Key Vault for secrets.
            • Penetration testing — annual third-party pen test (CrowdStrike); summary letter available under NDA.
            • Bug bounty — security@eusotrip.com (PGP key on the eusotrip.com/security page).

            ─────────────────────────────────────────────
            Data protection (GDPR / CCPA / CPRA / Quebec Law 25)
            ─────────────────────────────────────────────

            • Data Processing Addendum (DPA) — available to enterprise customers on request.
            • Subject Access Requests — 30-day response SLA via privacy@eusotrip.com.
            • Right to deletion — honored except where retention is required by law (HOS records §395.8(k) 6-month minimum, tax records 7-year minimum, financial records 5-year minimum).
            • Data Protection Officer — privacy@eusotrip.com.
            • Sub-processors — published at eusotrip.com/legal/subprocessors. We notify customers 30 days before adding a new sub-processor.

            ─────────────────────────────────────────────
            Insurance
            ─────────────────────────────────────────────

            • Cyber liability — $5M aggregate.
            • Errors & Omissions — $3M aggregate.
            • General liability — $2M per occurrence / $4M aggregate.
            • Certificate of Insurance available on request: insurance@eusotrip.com.

            ─────────────────────────────────────────────
            Contact
            ─────────────────────────────────────────────

            • Compliance: compliance@eusotrip.com
            • Security: security@eusotrip.com
            • Data protection: privacy@eusotrip.com
            • Legal: legal@eusotrip.com
            • Insurance: insurance@eusotrip.com
            """
        }
    }
}

// MARK: - About this app (Apple-style)

struct AboutThisAppSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    /// When presented in-stack via `\.rolePushDetail`, the surface's
    /// `BespokeBackBar` provides the chevron, so the sheet's own X is
    /// suppressed (no chevron + X). Modal presenters keep it (default).
    var showsCloseButton: Bool = true

    private var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if showsCloseButton {
                HStack {
                    Spacer(minLength: 0)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Space.s4)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: Space.s5) {
                    // Brand lockup — gradient orb + wordmark
                    VStack(spacing: Space.s3) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient.diagonal)
                                .frame(width: 96, height: 96)
                            Image(systemName: "sparkles")
                                .font(.system(size: 40, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: Brand.blue.opacity(0.45), radius: 18, y: 6)
                        Text("EusoTrip")
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("Logistics, reimagined.")
                            .font(EType.body)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.top, Space.s3)

                    // Version / build
                    LifecycleCard {
                        LifecycleRow(label: "Version", value: marketingVersion)
                        LifecycleRow(label: "Build",   value: buildNumber)
                        LifecycleRow(label: "Platform", value: "iOS")
                    }

                    // Credits
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: Space.s3) {
                            Text("CREDITS")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                                .foregroundStyle(palette.textTertiary)
                            Text("Designed & Engineered by\nEusorone Technologies, Inc")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(palette.textPrimary)
                                .multilineTextAlignment(.leading)
                            Text("in Austin, TX")
                                .font(EType.body)
                                .foregroundStyle(palette.textSecondary)
                            Divider().background(palette.borderFaint)
                            Text("Code written by")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                                .foregroundStyle(palette.textTertiary)
                            Text("Mike \"Diego\" Usoro")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(LinearGradient.diagonal)
                            Divider().background(palette.borderFaint)
                            Text("Powered by ESANG AI™")
                                .font(EType.caption)
                                .foregroundStyle(palette.textTertiary)
                        }
                    }

                    // Brand systems
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("BRANDED SYSTEMS")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                                .foregroundStyle(palette.textTertiary)
                            ForEach([
                                ("ESANG AI",      "AI dispatch + decision audit"),
                                ("EusoTicket",    "BOL · Run Ticket · Haul Receipt"),
                                ("EusoWallet",    "Settlements · payments · escrow"),
                                ("Zeun",          "Fleet maintenance · breakdown · provider network"),
                                ("The Haul",      "Driver gamification · missions · leaderboard"),
                                ("SpectraMatch",  "Catalyst load matching"),
                            ], id: \.0) { system, desc in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(system)
                                        .font(EType.bodyStrong)
                                        .foregroundStyle(LinearGradient.diagonal)
                                    Text(desc)
                                        .font(EType.caption)
                                        .foregroundStyle(palette.textSecondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    // Copyright
                    Text("© 2026 Eusorone Technologies, Inc.\nAll rights reserved.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, Space.s8)
                }
                .padding(.horizontal, Space.s5)
            }
        }
        .background(palette.bgPrimary)
    }
}

// MARK: - Previews

#Preview("348 · Legal · Night") {
    LegalScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("348 · Legal · Afternoon") {
    LegalScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("About this app · Dark") {
    AboutThisAppSheet()
        .preferredColorScheme(.dark)
}
