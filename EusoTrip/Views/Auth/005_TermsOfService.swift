//
//  005_TermsOfService.swift
//  EusoTrip — Terms of Service surface.
//
//  Canonical legal copy ported verbatim from the web platform
//  (frontend/client/src/pages/TermsOfService.tsx).
//  Effective: February 5, 2025 · Eusorone Technologies Inc.
//

import SwiftUI

struct TermsOfServiceView: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<String> = ["acceptance"]

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                titleBar
                IridescentHairline()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        header
                        bindingNotice
                        expandCollapseControls
                        ForEach(Self.sections, id: \.id) { s in
                            sectionCard(s)
                        }
                        contactCard
                        footer
                    }
                    .padding(Space.s5)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        // Uniform cafe-door entrance.
        .screenTileRoot()
    }

    // MARK: - Bars

    private var titleBar: some View {
        HStack {
            Text("Terms of Service")
                .font(EType.h2)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Done") { dismiss() }
                .font(EType.bodyStrong)
                .foregroundStyle(LinearGradient.diagonal)
        }
        .padding(.horizontal, Space.s5)
        .padding(.vertical, Space.s4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Terms of Service")
                .font(EType.h1)
                .foregroundStyle(LinearGradient.diagonal)
            Text("Eusorone Technologies Inc. — EusoTrip Freight & Energy Logistics Platform")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: Space.s3) {
                Label("Effective: February 5, 2025", systemImage: "calendar")
                Label("Last Updated: February 5, 2025", systemImage: "calendar")
            }
            .font(EType.micro).tracking(0.3)
            .foregroundStyle(palette.textTertiary)
            .padding(.top, 4)
        }
    }

    private var bindingNotice: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.amber400)
            VStack(alignment: .leading, spacing: 6) {
                Text("LEGALLY BINDING AGREEMENT")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(Color.amber300)
                Text("These Terms of Service constitute a legally binding contract between you and Eusorone Technologies Inc. By using EusoTrip, you agree to be bound by these Terms, including the mandatory arbitration clause, class action waiver, and anti-circumvention provisions. If you do not agree, do not use the Platform.")
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineSpacing(2)
            }
        }
        .padding(Space.s4)
        .background(Color.amber400.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Color.amber400.opacity(0.3)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var expandCollapseControls: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Expand All") {
                expanded = Set(Self.sections.map(\.id))
            }
            .font(EType.micro)
            .foregroundStyle(Color.blue400)
            Text("|").foregroundStyle(palette.textTertiary)
            Button("Collapse All") { expanded.removeAll() }
                .font(EType.micro)
                .foregroundStyle(Color.blue400)
        }
    }

    private func sectionCard(_ s: Section) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if expanded.contains(s.id) { expanded.remove(s.id) }
                    else { expanded.insert(s.id) }
                }
            } label: {
                HStack(spacing: Space.s3) {
                    Image(systemName: s.sfSymbol)
                        .foregroundStyle(s.iconTint)
                        .frame(width: 22)
                    Text(s.title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if s.highlight {
                        Text("IMPORTANT")
                            .font(EType.micro).tracking(0.8)
                            .foregroundStyle(Color.amber400)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.amber400.opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: 99)
                                .strokeBorder(Color.amber400.opacity(0.3)))
                            .clipShape(RoundedRectangle(cornerRadius: 99))
                    }
                    Image(systemName: expanded.contains(s.id) ? "chevron.down" : "chevron.right")
                        .foregroundStyle(palette.textTertiary)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(Space.s4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded.contains(s.id) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Divider().background(palette.borderFaint)
                        .padding(.bottom, 4)
                    ForEach(Array(s.blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s4)
            }
        }
        .background(palette.bgCard.opacity(0.85))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(s.highlight ? Color.amber400.opacity(0.3) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .lineSpacing(2)
        case .emphasized(let text):
            Text(text)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineSpacing(2)
        case .notice(let text):
            Text(text)
                .font(EType.bodyStrong).tracking(0.3)
                .foregroundStyle(Color.amber300)
                .lineSpacing(2)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(palette.textTertiary)
                        Text(item)
                            .font(EType.body)
                            .foregroundStyle(palette.textPrimary)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(.leading, 4)
        }
    }

    private var contactCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "envelope.fill").foregroundStyle(Color.cyan400)
            VStack(alignment: .leading, spacing: 4) {
                Text("Questions About These Terms?")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Contact our Legal Department at legal@eusorone.com")
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
                Text("Data Protection Officer: privacy@eusorone.com")
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
                Text("Eusorone Technologies Inc. | EusoTrip Freight & Energy Logistics Platform")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 4)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard.opacity(0.85))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var footer: some View {
        Text("Copyright \(Self.currentYear) Eusorone Technologies Inc. All rights reserved.")
            .font(EType.micro)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, Space.s3)
    }

    private static var currentYear: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f.string(from: Date())
    }

    // MARK: - Model

    private enum Block {
        case paragraph(String)
        case emphasized(String)   // bold leading clause (e.g. "THIS SECTION IS A MATERIAL TERM…")
        case notice(String)       // amber highlight (binding arbitration notice)
        case bullets([String])
    }

    private struct Section {
        let id: String
        let title: String
        let sfSymbol: String
        let iconTint: Color
        let highlight: Bool
        let blocks: [Block]
    }

    // MARK: - Sections (ported verbatim from web ToS, Feb 5 2025)

    private static let sections: [Section] = [
        Section(
            id: "acceptance",
            title: "1. Acceptance of Terms & Agreement to Be Bound",
            sfSymbol: "hammer.fill",
            iconTint: Color.blue400,
            highlight: true,
            blocks: [
                .paragraph("By accessing, browsing, registering for, or using the EusoTrip platform (the \"Platform\"), operated by Eusorone Technologies Inc. (\"Company,\" \"we,\" \"us,\" or \"our\"), you (\"User,\" \"you,\" or \"your\") acknowledge that you have read, understood, and agree to be legally bound by these Terms of Service (\"Terms\"), our Privacy Policy, and all applicable laws and regulations, including but not limited to the Federal Motor Catalyst Safety Regulations (FMCSRs, 49 CFR Parts 350-399), Pipeline and Hazardous Materials Safety Administration (PHMSA) regulations (49 CFR Parts 100-185), Federal Aviation Administration (FAA) rules as applicable, the Electronic Signatures in Global and National Commerce Act (E-SIGN Act, 15 U.S.C. 7001-7031), the Uniform Electronic Transactions Act (UETA), and all applicable state transportation and commercial codes."),
                .emphasized("IF YOU DO NOT AGREE TO ALL OF THESE TERMS, YOU MUST NOT ACCESS OR USE THE PLATFORM. YOUR CONTINUED USE OF THE PLATFORM CONSTITUTES YOUR ONGOING ACCEPTANCE OF THESE TERMS AS AMENDED FROM TIME TO TIME."),
                .paragraph("These Terms constitute a legally binding agreement between you and Eusorone Technologies Inc. By clicking \"I Accept,\" \"I Agree,\" creating an account, or using any part of the Platform, you represent and warrant that you are at least 18 years old, have the legal capacity to enter into this agreement, and if acting on behalf of a company or entity, have the authority to bind that entity to these Terms."),
                .paragraph("We reserve the right to modify these Terms at any time. Material changes will be communicated via email, in-platform notification, or posting on the Platform with a revised \"Last Updated\" date. Your continued use after such changes constitutes acceptance of the modified Terms.")
            ]
        ),
        Section(
            id: "platform-description",
            title: "2. Platform Description & Scope of Services",
            sfSymbol: "truck.box.fill",
            iconTint: Color.green400,
            highlight: false,
            blocks: [
                .paragraph("EusoTrip is a comprehensive freight and energy logistics technology platform that facilitates the connection of Shippers, Catalysts, Brokers, Drivers, Dispatchers (Dispatch), Escort/Pilot Vehicle Operators, Terminal Managers, Compliance Officers, Safety Managers, and other transportation industry participants (\"Users\"). The Platform provides tools for:"),
                .bullets([
                    "Load posting, searching, matching, and booking across all commodity types including but not limited to hazardous materials, crude oil, refined petroleum products, chemicals, dry goods, agricultural products, and oversized/overweight freight",
                    "Real-time GPS tracking, Hours of Service (HOS) monitoring, and Electronic Logging Device (ELD) compliance",
                    "Automated dispatch, route optimization, and fleet management",
                    "Digital bill of lading (BOL), proof of delivery (POD), rate confirmations, and document management",
                    "Bidding, rate negotiation, and marketplace transactions",
                    "Regulatory compliance management (FMCSA, PHMSA, DOT, EPA, OSHA, TSA, EIA)",
                    "Financial services including invoicing, factoring, wallet, and payment processing",
                    "Emergency response coordination, supply chain disruption management, and crisis mobilization",
                    "Gamification, rewards, and driver incentive programs (\"The Haul\")",
                    "AI-powered analytics, crude oil identification (SpectraMatch), and emergency response guidance (ERG)",
                    "Communication, messaging, and collaboration tools"
                ]),
                .emphasized("The Platform is a technology marketplace and intermediary."),
                .paragraph("Eusorone Technologies Inc. does not itself transport goods, operate vehicles, employ drivers, or act as a motor catalyst, freight broker, or freight forwarder unless separately licensed and disclosed. The Platform facilitates connections between independent parties who negotiate and execute transportation services directly.")
            ]
        ),
        Section(
            id: "user-accounts",
            title: "3. User Accounts, Registration & Verification",
            sfSymbol: "person.2.fill",
            iconTint: Color.purple400,
            highlight: false,
            blocks: [
                .paragraph("3.1 Account Registration. To use the Platform, you must create an account and provide accurate, complete, and current information during registration. You agree to update your information promptly if it changes. Providing false, misleading, or outdated information is grounds for immediate account termination."),
                .paragraph("3.2 Role-Specific Requirements. Depending on your selected role, you may be required to provide and maintain valid:"),
                .bullets([
                    "Shippers: PHMSA registration (if shipping hazmat), EPA ID (if applicable), commodity classifications, insurance certificates",
                    "Catalysts: USDOT number, MC/MX authority, operating authority, FMCSA safety rating, insurance ($1M+ liability, cargo coverage), BOC-3 filing",
                    "Brokers: Broker authority (MC number), surety bond or trust fund ($75,000 minimum per 49 CFR 387.307), insurance",
                    "Drivers: Valid CDL (Class A or B), medical examiner's certificate (per 49 CFR 391.41-391.49), endorsements as applicable (H, N, T, X, P, S), TWIC card (if accessing MTSA-regulated facilities), TSA security threat assessment (if hauling hazmat)",
                    "Terminal Managers: Facility EPA ID, SPCC plan, state permits, OSHA compliance documentation",
                    "Escorts: State pilot/escort certifications, vehicle insurance, required equipment"
                ]),
                .paragraph("3.3 Verification. We reserve the right to verify all credentials, licenses, registrations, insurance, and other documentation at any time. Failure to pass verification or maintain current credentials may result in account suspension or termination."),
                .paragraph("3.4 Account Security. You are solely responsible for maintaining the confidentiality of your account credentials. You agree to notify us immediately of any unauthorized access. You are liable for all activities conducted through your account.")
            ]
        ),
        Section(
            id: "anti-circumvention",
            title: "4. Anti-Circumvention & Platform Exclusivity",
            sfSymbol: "nosign",
            iconTint: Color.red400,
            highlight: true,
            blocks: [
                .notice("THIS SECTION IS A MATERIAL TERM OF THIS AGREEMENT. PLEASE READ IT CAREFULLY."),
                .paragraph("4.1 Non-Circumvention Covenant. You agree that for any business relationship, load, shipment, transportation arrangement, or commercial opportunity that was originated, discovered, introduced, facilitated, matched, or negotiated through the EusoTrip Platform (an \"Originated Relationship\"), you shall not, directly or indirectly:"),
                .bullets([
                    "(a) Contact, solicit, negotiate with, or transact business with any other Platform User outside of the Platform for the purpose of circumventing, avoiding, or reducing any fee, commission, or payment owed to Eusorone Technologies Inc.;",
                    "(b) Exchange personal contact information (phone numbers, email addresses, physical addresses, social media handles, or any other direct communication channel) with other Platform Users for the purpose of conducting transactions that would otherwise occur through the Platform;",
                    "(c) Arrange, book, dispatch, or execute any load, shipment, or transportation service that was posted, matched, or identified through the Platform by communicating directly with the counterparty outside the Platform to avoid Platform fees;",
                    "(d) Use information obtained through the Platform (including but not limited to shipper identities, catalyst capacities, load origins/destinations, rate information, lane data, or driver availability) to conduct off-platform transactions;",
                    "(e) Divert, redirect, or reassign any load or shipment that was booked through the Platform to an off-platform arrangement;",
                    "(f) Create, maintain, or use any parallel communication channel, third-party tool, or workaround designed to replicate Platform functionality while avoiding Platform fees;",
                    "(g) Encourage, assist, or conspire with any other User to engage in any of the foregoing prohibited conduct."
                ]),
                .paragraph("4.2 Duration of Non-Circumvention. The non-circumvention obligations under Section 4.1 apply: (a) for the duration of your active account; and (b) for a period of twenty-four (24) months following the last transaction between you and any specific counterparty that was originated through the Platform, regardless of whether your account remains active."),
                .paragraph("4.3 Pre-Existing Relationships. The non-circumvention obligations do not apply to business relationships that you can demonstrate, with documentary evidence, existed prior to either party's registration on the Platform. The burden of proof lies with the User claiming a pre-existing relationship."),
                .paragraph("4.4 Monitoring & Detection. You acknowledge and consent that Eusorone Technologies Inc. may employ reasonable monitoring tools, pattern analysis, and algorithmic detection to identify potential circumvention activity, including but not limited to analyzing transaction patterns, load volumes, communication metadata, and booking frequency between Users."),
                .paragraph("4.5 Remedies for Circumvention. In the event of a breach of this Section 4, Eusorone Technologies Inc. shall be entitled to, without limitation:"),
                .bullets([
                    "(a) Immediate suspension or permanent termination of your account;",
                    "(b) Recovery of all fees, commissions, and revenue that would have been earned by Eusorone Technologies Inc. had the circumvented transactions been conducted through the Platform, plus a penalty equal to two times (2x) the estimated lost revenue (\"Circumvention Fee\");",
                    "(c) Recovery of all costs and attorneys' fees incurred in enforcing this provision;",
                    "(d) Injunctive relief, including temporary restraining orders and preliminary and permanent injunctions, without the necessity of proving actual damages or posting a bond, as circumvention would cause irreparable harm for which monetary damages are inadequate;",
                    "(e) Forfeiture of any outstanding payments, credits, rewards, or balances in your Platform accounts;",
                    "(f) Reporting to applicable regulatory authorities if circumvention involves regulatory violations (e.g., operating without authority, insurance fraud, or safety violations)."
                ]),
                .paragraph("4.6 Liquidated Damages. You agree that the Circumvention Fee described in Section 4.5(b) constitutes a reasonable estimate of the damages that would be incurred by Eusorone Technologies Inc. in the event of circumvention and is not a penalty. You acknowledge that actual damages would be difficult to calculate and that this liquidated damages provision is fair and reasonable."),
                .paragraph("4.7 Reporting Obligation. If you become aware of any other User attempting to circumvent these Terms, you have an affirmative obligation to report such activity to Eusorone Technologies Inc. through the Platform's reporting mechanisms.")
            ]
        ),
        Section(
            id: "fees-payments",
            title: "5. Fees, Payments & Financial Terms",
            sfSymbol: "dollarsign.circle.fill",
            iconTint: Color.blue400,
            highlight: false,
            blocks: [
                .paragraph("5.1 Platform Fees. Eusorone Technologies Inc. charges fees for use of the Platform, which may include transaction fees, subscription fees, listing fees, premium feature fees, factoring fees, and/or commissions on loads booked through the Platform. Current fee schedules are available in the Platform and may be updated from time to time with 30 days' notice."),
                .paragraph("5.2 Payment Obligations. All fees are non-refundable except as expressly stated. You authorize Eusorone Technologies Inc. to charge fees to your designated payment method. Late payments accrue interest at the lesser of 1.5% per month or the maximum rate permitted by law."),
                .paragraph("5.3 Escrow & Payment Processing. When the Platform facilitates payments between Users (e.g., freight charges from Shippers to Catalysts), Eusorone Technologies Inc. may hold funds in escrow until delivery confirmation. Eusorone Technologies Inc. is not liable for disputes between Users regarding payment amounts, freight charges, accessorial charges, or detention/demurrage fees."),
                .paragraph("5.4 Factoring. If you use the Platform's factoring services, separate factoring terms and a notice of assignment will govern those transactions. Factoring rates, advance percentages, and reserve amounts will be disclosed prior to activation."),
                .paragraph("5.5 Taxes. You are solely responsible for all applicable federal, state, and local taxes arising from your use of the Platform and your transportation operations. Eusorone Technologies Inc. may issue 1099 forms as required by law."),
                .paragraph("5.6 Chargebacks & Disputes. Unauthorized chargebacks or payment reversals may result in account suspension, collections action, and/or reporting to credit bureaus. Payment disputes must be submitted through the Platform's dispute resolution process within 30 days of the transaction.")
            ]
        ),
        Section(
            id: "user-conduct",
            title: "6. User Conduct & Prohibited Activities",
            sfSymbol: "exclamationmark.triangle.fill",
            iconTint: Color.amber400,
            highlight: false,
            blocks: [
                .paragraph("You agree not to, and shall not permit any third party to:"),
                .bullets([
                    "Use the Platform for any unlawful purpose or in violation of any federal, state, or local law or regulation",
                    "Provide false, inaccurate, or misleading information in connection with your account, loads, bids, credentials, or any other Platform feature",
                    "Operate a commercial motor vehicle without valid operating authority, insurance, or driver qualifications as required by FMCSA regulations",
                    "Transport hazardous materials without proper placarding, shipping papers, training (per 49 CFR 172 Subpart H), or endorsements",
                    "Violate Hours of Service regulations (49 CFR Part 395), falsify ELD records, or encourage or coerce any driver to violate HOS rules",
                    "Engage in double brokering (re-brokering loads without authorization) in violation of 49 CFR 371.3",
                    "Impersonate any person or entity, or misrepresent your affiliation with any person or entity",
                    "Interfere with, disrupt, or attempt to gain unauthorized access to the Platform's servers, networks, or infrastructure",
                    "Reverse engineer, decompile, disassemble, or attempt to derive the source code of the Platform",
                    "Use automated scripts, bots, crawlers, or scraping tools to collect data from the Platform",
                    "Manipulate bidding, ratings, reviews, or any other marketplace mechanism",
                    "Harass, threaten, discriminate against, or defame any other User",
                    "Post or transmit any content that is obscene, defamatory, or infringes on any intellectual property right",
                    "Engage in or facilitate cargo theft, insurance fraud, identity fraud, or any other criminal activity",
                    "Use the Platform to facilitate human trafficking, smuggling, or transport of illegal substances",
                    "Collude with other Users to fix prices, allocate markets, or engage in any antitrust violation"
                ])
            ]
        ),
        Section(
            id: "regulatory-compliance",
            title: "7. Regulatory Compliance & Safety Obligations",
            sfSymbol: "shield.fill",
            iconTint: Color.cyan400,
            highlight: false,
            blocks: [
                .paragraph("7.1 General Compliance. Each User is independently responsible for complying with all applicable federal, state, local, and international laws and regulations governing their operations, including but not limited to:"),
                .bullets([
                    "Federal Motor Catalyst Safety Act and FMCSRs (49 CFR Parts 350-399)",
                    "Hazardous Materials Transportation Act (49 U.S.C. 5101-5128) and PHMSA regulations (49 CFR Parts 100-185)",
                    "OSHA standards (29 CFR Part 1910 and 1926)",
                    "EPA regulations including RCRA, CERCLA, Clean Water Act, and Clean Air Act",
                    "TSA Transportation Worker Identification Credential (TWIC) requirements (49 CFR Part 1572)",
                    "Drug and alcohol testing requirements (49 CFR Part 382 and Part 40)",
                    "Commercial Driver's License standards (49 CFR Part 383)",
                    "State oversize/overweight permit requirements",
                    "International trade and customs regulations (if applicable)"
                ]),
                .paragraph("7.2 Insurance Requirements. All Catalysts and Drivers must maintain minimum insurance coverage as required by 49 CFR Part 387 and as specified during registration. Proof of insurance must be kept current on the Platform. Lapse of insurance results in automatic account suspension."),
                .paragraph("7.3 Safety Reporting. Users must promptly report through the Platform any accidents, spills, releases, security incidents, or near-misses occurring in connection with Platform-facilitated transportation. Failure to report required incidents may result in account suspension and regulatory referral."),
                .paragraph("7.4 No Coercion. No User shall use the Platform to coerce any driver to operate a vehicle in violation of safety regulations, including HOS rules, vehicle inspection requirements, or hazardous materials handling procedures (per 49 CFR 390.6).")
            ]
        ),
        Section(
            id: "intellectual-property",
            title: "8. Intellectual Property Rights",
            sfSymbol: "lock.fill",
            iconTint: Color.indigo400,
            highlight: false,
            blocks: [
                .paragraph("8.1 Platform Ownership. The Platform, including all software, algorithms, designs, text, graphics, logos, icons, images, audio clips, data compilations, APIs, and all other content and materials (collectively, \"Platform IP\"), is the exclusive property of Eusorone Technologies Inc. or its licensors and is protected by U.S. and international copyright, trademark, patent, trade secret, and other intellectual property laws."),
                .paragraph("8.2 Limited License. Subject to your compliance with these Terms, Eusorone Technologies Inc. grants you a limited, non-exclusive, non-transferable, revocable license to access and use the Platform solely for your internal business purposes in connection with transportation and logistics operations."),
                .paragraph("8.3 Restrictions. You may not: (a) copy, modify, or create derivative works of the Platform IP; (b) license, sublicense, sell, resell, transfer, or distribute the Platform or any Platform IP; (c) use Eusorone Technologies Inc. or EusoTrip trademarks without prior written consent; (d) use any data mining, robots, or similar data gathering and extraction tools on the Platform."),
                .paragraph("8.4 User Content. You retain ownership of content you upload to the Platform (\"User Content\"). By uploading User Content, you grant Eusorone Technologies Inc. a worldwide, royalty-free, non-exclusive license to use, reproduce, modify, and display such content solely for the purpose of operating and improving the Platform."),
                .paragraph("8.5 Feedback. Any suggestions, ideas, or feedback you provide regarding the Platform become the property of Eusorone Technologies Inc. and may be used without obligation or compensation to you.")
            ]
        ),
        Section(
            id: "data-confidentiality",
            title: "9. Confidentiality & Data Use",
            sfSymbol: "eye.fill",
            iconTint: Color.violet400,
            highlight: false,
            blocks: [
                .paragraph("9.1 Confidential Information. All non-public information obtained through the Platform, including but not limited to rate information, lane data, shipper identities, catalyst capacities, driver information, load details, financial terms, and business strategies, constitutes \"Confidential Information.\" You agree not to disclose Confidential Information to any third party or use it for any purpose other than conducting transactions through the Platform."),
                .paragraph("9.2 Data Aggregation. Eusorone Technologies Inc. may aggregate and anonymize data from Platform usage for purposes of analytics, benchmarking, market insights, and Platform improvement. Aggregated data will not identify individual Users."),
                .paragraph("9.3 Regulatory Disclosure. Notwithstanding the foregoing, Eusorone Technologies Inc. may disclose User information as required by law, regulation, subpoena, court order, or government investigation, including to FMCSA, PHMSA, DOT, EPA, OSHA, TSA, law enforcement, or other regulatory authorities."),
                .paragraph("9.4 Data Security. We implement industry-standard security measures to protect your data. However, no electronic transmission or storage method is 100% secure. See our Privacy Policy for detailed information on our data handling practices.")
            ]
        ),
        Section(
            id: "disclaimers",
            title: "10. Disclaimers & Limitation of Liability",
            sfSymbol: "exclamationmark.circle.fill",
            iconTint: Color.orange400,
            highlight: false,
            blocks: [
                .paragraph("10.1 \"AS IS\" Disclaimer. THE PLATFORM IS PROVIDED \"AS IS\" AND \"AS AVAILABLE\" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT. EUSORONE TECHNOLOGIES INC. DOES NOT WARRANT THAT THE PLATFORM WILL BE UNINTERRUPTED, ERROR-FREE, SECURE, OR FREE OF VIRUSES OR OTHER HARMFUL COMPONENTS."),
                .paragraph("10.2 No Guarantee of Results. Eusorone Technologies Inc. does not guarantee: (a) that you will find loads, catalysts, drivers, or other business opportunities through the Platform; (b) the accuracy, reliability, or completeness of any information provided by other Users; (c) the creditworthiness, safety record, or regulatory compliance of any User; (d) the condition, quality, legality, or safety of any cargo, vehicle, or service."),
                .paragraph("10.3 Limitation of Liability. TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL EUSORONE TECHNOLOGIES INC., ITS OFFICERS, DIRECTORS, EMPLOYEES, AGENTS, AFFILIATES, SUCCESSORS, OR ASSIGNS BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, PUNITIVE, OR EXEMPLARY DAMAGES, INCLUDING BUT NOT LIMITED TO DAMAGES FOR LOSS OF PROFITS, GOODWILL, DATA, OR OTHER INTANGIBLE LOSSES, REGARDLESS OF THE THEORY OF LIABILITY (CONTRACT, TORT, NEGLIGENCE, STRICT LIABILITY, OR OTHERWISE), EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES."),
                .paragraph("10.4 Cap on Liability. EUSORONE TECHNOLOGIES INC.'S TOTAL AGGREGATE LIABILITY FOR ALL CLAIMS ARISING OUT OF OR RELATING TO THESE TERMS OR YOUR USE OF THE PLATFORM SHALL NOT EXCEED THE GREATER OF: (A) THE TOTAL FEES PAID BY YOU TO EUSORONE TECHNOLOGIES INC. DURING THE TWELVE (12) MONTHS PRECEDING THE CLAIM, OR (B) ONE THOUSAND DOLLARS ($1,000)."),
                .paragraph("10.5 Basis of the Bargain. You acknowledge that Eusorone Technologies Inc. has set its prices and entered into this agreement in reliance on the limitations of liability set forth herein, which allocate risk between you and Eusorone Technologies Inc. and form an essential basis of the bargain between the parties.")
            ]
        ),
        Section(
            id: "indemnification",
            title: "11. Indemnification",
            sfSymbol: "scale.3d",
            iconTint: Color.pink400,
            highlight: false,
            blocks: [
                .paragraph("You agree to indemnify, defend, and hold harmless Eusorone Technologies Inc., its officers, directors, employees, agents, affiliates, successors, and assigns (collectively, \"Indemnified Parties\") from and against any and all claims, damages, losses, liabilities, costs, and expenses (including reasonable attorneys' fees and court costs) arising out of or relating to:"),
                .bullets([
                    "Your use of or inability to use the Platform",
                    "Your violation of these Terms or any applicable law or regulation",
                    "Your violation of any rights of any third party, including intellectual property rights",
                    "Any transportation services you provide or receive through the Platform",
                    "Any accident, injury, death, environmental contamination, property damage, or cargo loss/damage occurring in connection with your operations",
                    "Your breach of the anti-circumvention provisions of Section 4",
                    "Any fines, penalties, or sanctions imposed by any regulatory authority in connection with your operations",
                    "Any content you post or transmit through the Platform",
                    "Any tax liability, including employment tax reclassification claims"
                ]),
                .paragraph("This indemnification obligation survives termination of your account and these Terms.")
            ]
        ),
        Section(
            id: "dispute-resolution",
            title: "12. Dispute Resolution, Arbitration & Governing Law",
            sfSymbol: "hammer.fill",
            iconTint: Color.pink400,
            highlight: true,
            blocks: [
                .notice("THIS SECTION CONTAINS A BINDING ARBITRATION CLAUSE AND CLASS ACTION WAIVER. PLEASE READ CAREFULLY."),
                .paragraph("12.1 Governing Law. These Terms are governed by and construed in accordance with the laws of the State of Texas, without regard to its conflict of law provisions. For any disputes not subject to arbitration, you consent to the exclusive jurisdiction of the state and federal courts located in Harris County, Texas."),
                .paragraph("12.2 Mandatory Arbitration. Any dispute, controversy, or claim arising out of or relating to these Terms, or the breach, termination, or validity thereof, shall be finally settled by binding arbitration administered by the American Arbitration Association (AAA) under its Commercial Arbitration Rules. The arbitration shall be conducted in Harris County, Texas before a single arbitrator with experience in transportation or technology disputes. The arbitrator's decision shall be final and binding and may be entered as a judgment in any court of competent jurisdiction."),
                .paragraph("12.3 Class Action Waiver. YOU AND EUSORONE TECHNOLOGIES INC. AGREE THAT ANY DISPUTE RESOLUTION PROCEEDINGS WILL BE CONDUCTED ONLY ON AN INDIVIDUAL BASIS AND NOT IN A CLASS, CONSOLIDATED, OR REPRESENTATIVE ACTION. YOU EXPRESSLY WAIVE YOUR RIGHT TO PARTICIPATE IN A CLASS ACTION LAWSUIT OR CLASS-WIDE ARBITRATION."),
                .paragraph("12.4 Small Claims Exception. Either party may bring an individual action in small claims court for disputes within the court's jurisdictional limit."),
                .paragraph("12.5 Injunctive Relief Exception. Notwithstanding the arbitration requirement, either party may seek injunctive or equitable relief in any court of competent jurisdiction to prevent actual or threatened infringement of intellectual property rights or violation of the anti-circumvention provisions of Section 4."),
                .paragraph("12.6 Statute of Limitations. Any claim arising out of or related to these Terms must be filed within one (1) year after the cause of action accrues or be permanently barred.")
            ]
        ),
        Section(
            id: "termination",
            title: "13. Termination & Suspension",
            sfSymbol: "nosign",
            iconTint: Color.red400,
            highlight: false,
            blocks: [
                .paragraph("13.1 Termination by You. You may terminate your account at any time by providing written notice through the Platform. Outstanding obligations, including unpaid fees, pending transactions, and active loads, must be settled before termination takes effect."),
                .paragraph("13.2 Termination by Us. Eusorone Technologies Inc. may suspend or terminate your account at any time, with or without cause and with or without notice, including for: (a) violation of these Terms; (b) fraudulent, illegal, or harmful activity; (c) lapse of required credentials or insurance; (d) failure to pay fees; (e) circumvention of Platform fees (Section 4); (f) safety concerns; (g) regulatory non-compliance; or (h) extended account inactivity."),
                .paragraph("13.3 Effect of Termination. Upon termination: (a) your license to use the Platform immediately ceases; (b) you must stop using the Platform and delete any downloaded Platform content; (c) Eusorone Technologies Inc. may retain your data as required by law and for legitimate business purposes; (d) Sections 4, 5, 8, 9, 10, 11, 12, 13.3, 14, and 15 survive termination."),
                .paragraph("13.4 No Liability for Termination. Eusorone Technologies Inc. shall not be liable to you or any third party for any suspension or termination of your account or access to the Platform.")
            ]
        ),
        Section(
            id: "independent-contractors",
            title: "14. Independent Contractor Relationship",
            sfSymbol: "building.2.fill",
            iconTint: Color.teal400,
            highlight: false,
            blocks: [
                .paragraph("14.1 No Employment Relationship. Users of the Platform are independent contractors and not employees, agents, joint venturers, or partners of Eusorone Technologies Inc. Nothing in these Terms creates an employer-employee relationship between Eusorone Technologies Inc. and any User, including Drivers, Catalysts, or Dispatchers."),
                .paragraph("14.2 No Authority to Bind. No User has the authority to bind Eusorone Technologies Inc. to any contract, obligation, or liability. Users shall not represent themselves as employees or agents of Eusorone Technologies Inc."),
                .paragraph("14.3 Tax Responsibility. Each User is solely responsible for their own tax obligations, including income taxes, self-employment taxes, sales taxes, fuel taxes (IFTA), and any other applicable taxes. Eusorone Technologies Inc. does not withhold taxes on behalf of Users."),
                .paragraph("14.4 Benefits. Users are not entitled to any employee benefits from Eusorone Technologies Inc., including but not limited to health insurance, retirement benefits, workers' compensation, unemployment insurance, or paid time off.")
            ]
        ),
        Section(
            id: "general",
            title: "15. General Provisions",
            sfSymbol: "book.fill",
            iconTint: Color.slate400,
            highlight: false,
            blocks: [
                .paragraph("15.1 Entire Agreement. These Terms, together with the Privacy Policy and any additional terms or policies referenced herein, constitute the entire agreement between you and Eusorone Technologies Inc. regarding the Platform and supersede all prior agreements and understandings."),
                .paragraph("15.2 Severability. If any provision of these Terms is held to be invalid, illegal, or unenforceable, the remaining provisions shall remain in full force and effect. The invalid provision shall be modified to the minimum extent necessary to make it valid and enforceable while preserving its original intent."),
                .paragraph("15.3 Waiver. The failure of Eusorone Technologies Inc. to enforce any provision of these Terms shall not constitute a waiver of that provision or any other provision."),
                .paragraph("15.4 Assignment. You may not assign or transfer these Terms or any rights hereunder without Eusorone Technologies Inc.'s prior written consent. Eusorone Technologies Inc. may freely assign these Terms."),
                .paragraph("15.5 Force Majeure. Eusorone Technologies Inc. shall not be liable for any delay or failure in performance resulting from causes beyond its reasonable control, including acts of God, natural disasters, pandemics, war, terrorism, government actions, civil unrest, power outages, internet failures, or labor disputes."),
                .paragraph("15.6 Notices. All legal notices to Eusorone Technologies Inc. must be sent to: legal@eusorone.com or by certified mail to our registered address. Notices to you may be sent to the email address associated with your account."),
                .paragraph("15.7 Headings. Section headings are for convenience only and shall not affect the interpretation of these Terms."),
                .paragraph("15.8 No Third-Party Beneficiaries. These Terms do not confer any rights on any third party.")
            ]
        )
    ]
}

// MARK: - Tailwind-style tokens used by legal surfaces (ported from web)

extension Color {
    static let amber300 = Color(hex: 0xFCD34D)
    static let amber400 = Color(hex: 0xFBBF24)
    static let blue400  = Color(hex: 0x60A5FA)
    static let green400 = Color(hex: 0x4ADE80)
    static let purple400 = Color(hex: 0xC084FC)
    static let red400   = Color(hex: 0xF87171)
    static let cyan400  = Color(hex: 0x22D3EE)
    static let indigo400 = Color(hex: 0x818CF8)
    static let violet400 = Color(hex: 0xA78BFA)
    static let orange400 = Color(hex: 0xFB923C)
    static let pink400  = Color(hex: 0xF472B6)
    static let teal400  = Color(hex: 0x2DD4BF)
    static let slate400 = Color(hex: 0x94A3B8)
}

// MARK: - Previews (Dark + Light)

#Preview("Terms · Dark") {
    TermsOfServiceView()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("Terms · Light") {
    TermsOfServiceView()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
