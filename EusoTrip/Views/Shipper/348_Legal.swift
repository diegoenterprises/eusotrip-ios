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
    @State private var presentingDoc: LegalDoc? = nil
    @State private var presentingAbout: Bool = false

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
                    Button { presentingAbout = true } label: {
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
        .sheet(isPresented: $presentingAbout) {
            AboutThisAppSheet()
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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.title)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Eusorone Technologies, Inc · Last updated 2026-05-07")
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

            The mobile app does not use HTTP cookies. The web platform (eusotrip.com) uses three categories:

            • Essential — session token, CSRF, auth state. Required for the platform to function.
            • Functional — remembered preferences (theme, last-viewed dashboard, time zone). Settable / deletable from your account preferences.
            • Analytics — anonymized aggregate usage. Helps us improve the product. Disable via Account → Preferences → Analytics.

            We do not use third-party advertising trackers.

            Contact: privacy@eusotrip.com
            """
        case .openSourceNotices:
            return """
            EusoTrip Open Source Notices

            EusoTrip uses the following open source components. Full license texts are bundled at /Resources/Licenses/.

            • Lottie iOS — Apache 2.0 — Airbnb Inc.
            • Swift Collections — Apache 2.0 — The Swift Project Authors
            • Swift Algorithms — Apache 2.0 — The Swift Project Authors
            • SwiftUI / WebKit / MapKit / WeatherKit — Apple platform frameworks.

            Server-side dependencies and license notices are published at eusotrip.com/legal/oss.

            All proprietary code in this app — including the Driver, Catalyst, Shipper, Broker, Dispatch, Terminal, Escort, Admin, Rail, and Vessel UI surfaces; the ESANG AI dispatcher; the EusoTicket, EusoWallet, Zeun, and HERE-backed routing layers; and the equipment animation system — is © Eusorone Technologies, Inc.
            """
        case .complianceAttestations:
            return """
            EusoTrip Compliance Attestations

            FMCSA / USDOT.
            EusoTrip surfaces real-time FMCSA SAFER, MCMIS, and SMS data via the platform's licensed integration. ELD data flows are §395 compliant; HOS clocks meet 11/14/70 limits.

            DOT Hazmat (49 CFR Subpart B).
            UN/PG/Class data is mirrored from the U.S. PHMSA ERG database and refreshed quarterly. CHEMTREC integration is available for hazmat carriers; EusoTicket BOLs render compliant placard + shipping name fields.

            SOC 2 Type II.
            Eusorone Technologies, Inc. operates a SOC 2 Type II audited security program. Reports are available to enterprise customers under NDA via security@eusotrip.com.

            CCPA / GDPR.
            See Privacy Policy. Data subject requests: privacy@eusotrip.com.

            Tax & 1099.
            EusoWallet generates 1099-NEC / 1099-MISC for eligible carriers; tax filings are surfaced in-app under Earnings → Tax.

            Contact: compliance@eusotrip.com
            """
        }
    }
}

// MARK: - About this app (Apple-style)

struct AboutThisAppSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
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
