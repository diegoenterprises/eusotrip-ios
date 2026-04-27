//
//  006_PrivacyPolicy.swift
//  EusoTrip — Privacy Policy surface.
//
//  Canonical copy ported verbatim from the web platform
//  (frontend/client/src/pages/PrivacyPolicy.tsx).
//  Effective: February 5, 2025 · Eusorone Technologies Inc.
//

import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<String> = ["introduction"]

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                titleBar
                IridescentHairline()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        header
                        commitmentBanner
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
            Text("Privacy Policy")
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
            Text("Privacy Policy")
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

    private var commitmentBanner: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "lock.fill")
                .foregroundStyle(Color.emerald400)
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR PRIVACY MATTERS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(Color.emerald300)
                Text("We are committed to protecting your personal information. This policy explains what data we collect, how we use it, who we share it with, and your rights. We comply with CCPA, TDPSA, VCDPA, and other applicable privacy laws. We do not sell your personal information.")
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineSpacing(2)
            }
        }
        .padding(Space.s4)
        .background(Color.emerald400.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Color.emerald400.opacity(0.3)))
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
                        Text("KEY")
                            .font(EType.micro).tracking(0.8)
                            .foregroundStyle(Color.emerald400)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.emerald400.opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: 99)
                                .strokeBorder(Color.emerald400.opacity(0.3)))
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
                    .strokeBorder(s.highlight ? Color.emerald400.opacity(0.3) : palette.borderFaint))
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
                Text("Privacy Questions or Data Requests?")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Data Protection Officer: privacy@eusorone.com")
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
                Text("Legal Department: legal@eusorone.com")
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
        case emphasized(String)
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

    // MARK: - Sections (ported verbatim from web Privacy Policy, Feb 5 2025)

    private static let sections: [Section] = [
        Section(
            id: "introduction",
            title: "1. Introduction & Scope",
            sfSymbol: "shield.fill",
            iconTint: Color.blue400,
            highlight: false,
            blocks: [
                .paragraph("Eusorone Technologies Inc. (\"Company,\" \"we,\" \"us,\" or \"our\") operates the EusoTrip freight and energy logistics platform (the \"Platform\"). This Privacy Policy describes how we collect, use, disclose, store, and protect your personal information when you access or use the Platform, visit our website, or interact with us in any way."),
                .paragraph("This Privacy Policy applies to all Users of the Platform, including Shippers, Catalysts, Brokers, Drivers, Dispatchers (Dispatch), Escort/Pilot Vehicle Operators, Terminal Managers, Compliance Officers, Safety Managers, and all other registered and unregistered visitors."),
                .paragraph("By using the Platform, you consent to the data practices described in this Privacy Policy. If you do not agree with this Privacy Policy, please do not use the Platform. This Privacy Policy is incorporated into and subject to our Terms of Service."),
                .paragraph("We are committed to complying with applicable privacy and data protection laws, including but not limited to the California Consumer Privacy Act (CCPA/CPRA, Cal. Civ. Code 1798.100 et seq.), the Texas Data Privacy and Security Act (TDPSA), the Virginia Consumer Data Protection Act (VCDPA), the Colorado Privacy Act (CPA), the Connecticut Data Privacy Act (CTDPA), the Gramm-Leach-Bliley Act (GLBA) to the extent applicable to financial services, and applicable provisions of the European General Data Protection Regulation (GDPR) for any EU/EEA users.")
            ]
        ),
        Section(
            id: "information-collected",
            title: "2. Information We Collect",
            sfSymbol: "externaldrive.fill",
            iconTint: Color.green400,
            highlight: true,
            blocks: [
                .emphasized("2.1 Information You Provide Directly:"),
                .bullets([
                    "Account & Registration Data: Name, email address, phone number, mailing address, company name, job title, role selection, username, and password",
                    "Identity & Credential Data: Commercial Driver's License (CDL) number and state, CDL endorsements, TWIC card number, medical examiner's certificate, USDOT number, MC/MX authority number, FMCSA safety rating, employer identification number (EIN), Social Security Number (last 4 digits for verification), date of birth",
                    "Insurance & Financial Data: Insurance policy numbers and coverage amounts, surety bond information, bank account details (for payments/factoring), payment card information (processed via PCI-DSS compliant third-party processors), tax identification information",
                    "Regulatory & Compliance Data: PHMSA registration numbers, EPA IDs, hazmat training certificates, drug and alcohol testing program enrollment, CSA scores, inspection history, accident history, safety audit documentation",
                    "Operational Data: Load details (origin, destination, commodity, weight, dimensions, special handling), rate information, bid amounts, contract terms, delivery schedules, proof of delivery documents, bills of lading, shipping papers",
                    "Communications: Messages sent through the Platform, support tickets, feedback, reviews, ratings, and any other content you submit",
                    "Vehicle & Equipment Data: Vehicle identification numbers (VIN), license plate numbers, vehicle specifications, trailer information, maintenance records, inspection reports"
                ]),
                .emphasized("2.2 Information Collected Automatically:"),
                .bullets([
                    "GPS & Location Data: Real-time location data from driver mobile devices and ELD-equipped vehicles during active loads, geofence entry/exit events, route history, speed data, idle time (collected with your consent and as required for ELD compliance under 49 CFR Part 395)",
                    "Device & Technical Data: IP address, browser type and version, operating system, device identifiers, mobile device type, screen resolution, language preferences, referring URLs",
                    "Usage Data: Pages visited, features used, click patterns, search queries, session duration, load views, bid activity, login timestamps, feature engagement metrics",
                    "ELD & Telematics Data: Hours of Service records, engine diagnostics, fuel consumption, hard braking events, acceleration patterns, vehicle fault codes (collected from integrated ELD and telematics systems)",
                    "Cookies & Tracking Technologies: We use cookies, web beacons, pixels, and similar technologies as described in Section 8 below"
                ]),
                .emphasized("2.3 Information from Third Parties:"),
                .bullets([
                    "FMCSA/SAFER Data: Catalyst safety ratings, authority status, insurance filing status, inspection and crash data from FMCSA SAFER system",
                    "Credit & Background Checks: Credit reports (with your authorization), criminal background check results, MVR (Motor Vehicle Records) reports, employment verification",
                    "Identity Verification Services: Results from third-party identity verification, document authentication, and fraud detection services",
                    "Payment Processors: Transaction confirmation data, chargeback notifications, fraud alerts from payment processing partners",
                    "Insurance Verification: Insurance status updates from catalyst insurance databases and verification services"
                ])
            ]
        ),
        Section(
            id: "how-we-use",
            title: "3. How We Use Your Information",
            sfSymbol: "eye.fill",
            iconTint: Color.purple400,
            highlight: false,
            blocks: [
                .paragraph("We use the information we collect for the following purposes:"),
                .emphasized("3.1 Platform Operations & Service Delivery:"),
                .bullets([
                    "Creating and managing your account and verifying your identity and credentials",
                    "Facilitating load matching, bidding, booking, and transportation management",
                    "Processing payments, invoices, factoring, and financial transactions",
                    "Providing real-time tracking, dispatch, and fleet management services",
                    "Managing compliance documentation and regulatory reporting",
                    "Operating gamification features, rewards programs, and driver incentives",
                    "Facilitating communications between Users through in-platform messaging",
                    "Providing AI-powered analytics, SpectraMatch crude oil identification, and ERG guidance"
                ]),
                .emphasized("3.2 Safety & Regulatory Compliance:"),
                .bullets([
                    "Monitoring Hours of Service compliance and ELD data as required by 49 CFR Part 395",
                    "Verifying CDL status, endorsements, medical certificates, and driver qualifications per 49 CFR Part 391",
                    "Monitoring hazardous materials shipping compliance per 49 CFR Parts 171-180",
                    "Conducting drug and alcohol testing program administration per 49 CFR Part 382",
                    "Reporting required safety data to FMCSA, PHMSA, DOT, and other regulatory agencies",
                    "Emergency response coordination during supply chain disruptions or hazmat incidents"
                ]),
                .emphasized("3.3 Platform Integrity & Anti-Circumvention:"),
                .bullets([
                    "Detecting and preventing fraud, unauthorized access, and abuse of the Platform",
                    "Monitoring for potential circumvention of Platform fees as described in our Terms of Service",
                    "Analyzing transaction patterns to detect double brokering, cargo theft, and other prohibited conduct",
                    "Enforcing our Terms of Service and other Platform policies"
                ]),
                .emphasized("3.4 Analytics & Improvement:"),
                .bullets([
                    "Analyzing usage patterns to improve Platform features and user experience",
                    "Generating aggregated, anonymized market intelligence and benchmarking data",
                    "Developing new features, products, and services",
                    "Conducting research and development of AI and machine learning models"
                ]),
                .emphasized("3.5 Communications:"),
                .bullets([
                    "Sending transactional notifications (load updates, payment confirmations, bid alerts)",
                    "Sending safety alerts, emergency mobilization orders, and regulatory updates",
                    "Sending marketing and promotional communications (with your consent where required)",
                    "Responding to your inquiries and providing customer support"
                ])
            ]
        ),
        Section(
            id: "legal-bases",
            title: "4. Legal Bases for Processing",
            sfSymbol: "scale.3d",
            iconTint: Color.cyan400,
            highlight: false,
            blocks: [
                .paragraph("We process your personal information based on the following legal grounds:"),
                .bullets([
                    "Contract Performance: Processing necessary to perform our contract with you (the Terms of Service), including account creation, load management, payments, and service delivery",
                    "Legal Obligation: Processing necessary to comply with federal and state transportation regulations (FMCSA, PHMSA, DOT), tax laws, anti-money laundering requirements, and other legal obligations",
                    "Legitimate Interests: Processing necessary for our legitimate business interests, including fraud prevention, anti-circumvention enforcement, platform security, analytics, and service improvement, balanced against your privacy rights",
                    "Consent: Processing based on your explicit consent, including marketing communications, location tracking beyond regulatory requirements, and optional data sharing features. You may withdraw consent at any time without affecting the lawfulness of prior processing",
                    "Vital Interests: Processing necessary to protect vital interests in emergency response situations (e.g., hazmat spills, accidents, driver emergencies)"
                ])
            ]
        ),
        Section(
            id: "sharing-disclosure",
            title: "5. Information Sharing & Disclosure",
            sfSymbol: "square.and.arrow.up.fill",
            iconTint: Color.amber400,
            highlight: true,
            blocks: [
                .paragraph("We do not sell your personal information. We may share your information in the following circumstances:"),
                .paragraph("5.1 With Other Platform Users: When you use the Platform, certain information is shared with other Users as necessary for transactions. For example, Shippers see Catalyst company names and safety ratings; Catalysts see load details and pickup/delivery locations; Drivers' real-time locations are shared with dispatchers and load stakeholders during active deliveries."),
                .paragraph("5.2 Service Providers: We share information with trusted third-party service providers who assist us in operating the Platform, including:"),
                .bullets([
                    "Cloud hosting and infrastructure providers (data storage, computing)",
                    "Payment processors and financial service partners (PCI-DSS compliant)",
                    "Identity verification and background check providers",
                    "FMCSA/SAFER data providers and insurance verification services",
                    "Email and communication service providers",
                    "Analytics and monitoring tools",
                    "Customer support platforms"
                ]),
                .paragraph("All service providers are contractually bound to use your information only for the purposes we specify and to maintain appropriate security measures."),
                .paragraph("5.3 Regulatory & Government Authorities: We may disclose your information to regulatory agencies and government authorities as required by law, including:"),
                .bullets([
                    "FMCSA (safety data, inspection results, compliance records)",
                    "PHMSA (hazardous materials incident reports, registration data)",
                    "DOT (accident reports, safety data)",
                    "EPA (environmental incident reports, facility data)",
                    "OSHA (workplace safety incidents)",
                    "TSA (security threat assessments, TWIC-related inquiries)",
                    "IRS and state tax authorities (1099 reporting, tax compliance)",
                    "Law enforcement (in response to valid legal process, subpoenas, or court orders)"
                ]),
                .paragraph("5.4 Legal Proceedings: We may disclose information in connection with legal proceedings, including to enforce our Terms of Service, to protect our rights, property, or safety, or the rights, property, or safety of our Users or the public."),
                .paragraph("5.5 Business Transfers: In the event of a merger, acquisition, reorganization, bankruptcy, or sale of all or a portion of our assets, your information may be transferred as part of that transaction. We will notify you of any such change and any choices you may have regarding your information."),
                .paragraph("5.6 Aggregated & De-Identified Data: We may share aggregated, anonymized, or de-identified data that cannot reasonably be used to identify you for industry benchmarking, research, analytics, and marketing purposes.")
            ]
        ),
        Section(
            id: "data-retention",
            title: "6. Data Retention",
            sfSymbol: "server.rack",
            iconTint: Color.indigo400,
            highlight: false,
            blocks: [
                .paragraph("We retain your personal information for as long as necessary to fulfill the purposes described in this Privacy Policy, unless a longer retention period is required or permitted by law. Specific retention periods include:"),
                .bullets([
                    "Account Data: Retained for the duration of your active account plus 7 years after account termination (for tax, legal, and regulatory compliance purposes)",
                    "ELD/HOS Records: Retained for a minimum of 6 months as required by 49 CFR 395.8(k), and up to 3 years for compliance auditing",
                    "Driver Qualification Files: Retained for 3 years after the driver's employment/contract ends per 49 CFR 391.51",
                    "Drug & Alcohol Testing Records: Retained for 1-5 years depending on record type per 49 CFR Part 40",
                    "Financial & Transaction Records: Retained for 7 years per IRS and state tax requirements",
                    "Accident & Incident Records: Retained for 3 years per 49 CFR 390.15, or longer if related to ongoing litigation",
                    "Hazmat Shipping Records: Retained for 2 years per 49 CFR 172.201(e) or 3 years for hazardous waste manifests per EPA RCRA",
                    "Insurance Records: Retained for the policy period plus 3 years",
                    "Communication Records: Retained for 3 years after the last communication",
                    "GPS/Location Data: Retained for 6 months for active tracking purposes, then archived for up to 3 years for compliance and dispute resolution"
                ]),
                .paragraph("When retention periods expire, we securely delete or anonymize the data. We may retain de-identified or aggregated data indefinitely for analytics and research purposes.")
            ]
        ),
        Section(
            id: "data-security",
            title: "7. Data Security",
            sfSymbol: "lock.fill",
            iconTint: Color.blue400,
            highlight: false,
            blocks: [
                .paragraph("We implement comprehensive technical and organizational security measures to protect your personal information, including:"),
                .bullets([
                    "Encryption: TLS 1.3 encryption for all data in transit; AES-256 encryption for data at rest; encrypted database backups",
                    "Access Controls: Role-based access control (RBAC), multi-factor authentication for administrative access, principle of least privilege",
                    "Infrastructure Security: SOC 2 compliant cloud infrastructure, network segmentation, intrusion detection/prevention systems, DDoS protection, regular penetration testing",
                    "Payment Security: PCI-DSS compliant payment processing; we do not store raw credit card numbers on our servers",
                    "Monitoring: 24/7 security monitoring, automated anomaly detection, comprehensive audit logging",
                    "Incident Response: Documented incident response procedures, breach notification protocols in compliance with applicable state breach notification laws",
                    "Employee Training: Regular security awareness training for all personnel with access to user data",
                    "Vendor Security: Due diligence and contractual security requirements for all third-party service providers"
                ]),
                .paragraph("Despite our efforts, no method of electronic transmission or storage is 100% secure. We cannot guarantee absolute security but will promptly notify affected Users and applicable authorities in the event of a data breach as required by law.")
            ]
        ),
        Section(
            id: "cookies",
            title: "8. Cookies & Tracking Technologies",
            sfSymbol: "circle.grid.3x3.fill",
            iconTint: Color.orange400,
            highlight: false,
            blocks: [
                .paragraph("We use the following types of cookies and tracking technologies:"),
                .bullets([
                    "Strictly Necessary Cookies: Required for the Platform to function (authentication, session management, security tokens, load balancing). These cannot be disabled.",
                    "Functional Cookies: Remember your preferences and settings (language, role, dashboard layout, map preferences).",
                    "Analytics Cookies: Help us understand how Users interact with the Platform (page views, feature usage, error tracking). We use these to improve the Platform.",
                    "Performance Cookies: Monitor Platform performance, load times, and identify technical issues."
                ]),
                .paragraph("Managing Cookies: You can control cookies through your browser settings. Disabling certain cookies may limit Platform functionality. Strictly necessary cookies cannot be disabled without impacting core Platform operations."),
                .paragraph("Do Not Track: We currently respond to \"Do Not Track\" browser signals by disabling non-essential analytics cookies.")
            ]
        ),
        Section(
            id: "your-rights",
            title: "9. Your Privacy Rights",
            sfSymbol: "hand.raised.fill",
            iconTint: Color.pink400,
            highlight: true,
            blocks: [
                .paragraph("Depending on your jurisdiction, you may have the following rights regarding your personal information:"),
                .paragraph("9.1 Right to Know / Access (CCPA 1798.100, TDPSA, VCDPA, GDPR Art. 15): You have the right to request that we disclose what personal information we collect, use, disclose, and sell about you. You may request a copy of your personal information in a portable, machine-readable format."),
                .paragraph("9.2 Right to Delete (CCPA 1798.105, TDPSA, VCDPA, GDPR Art. 17): You have the right to request deletion of your personal information, subject to certain exceptions. We may retain information necessary for legal compliance (e.g., ELD records, driver qualification files, tax records), fraud prevention, exercising or defending legal claims, or as otherwise permitted by law."),
                .paragraph("9.3 Right to Correct (CCPA 1798.106, TDPSA, GDPR Art. 16): You have the right to request correction of inaccurate personal information. You can update most information directly through your account settings."),
                .paragraph("9.4 Right to Opt-Out of Sale (CCPA 1798.120): We do not sell your personal information as defined by the CCPA. If this changes, we will provide a clear opt-out mechanism."),
                .paragraph("9.5 Right to Non-Discrimination (CCPA 1798.125): We will not discriminate against you for exercising your privacy rights. However, some features require certain data to function (e.g., GPS tracking for active load tracking, credential data for compliance verification)."),
                .paragraph("9.6 Right to Data Portability (GDPR Art. 20, VCDPA): Where technically feasible, you may request your personal information in a structured, commonly used, machine-readable format."),
                .paragraph("9.7 Right to Restrict Processing (GDPR Art. 18): In certain circumstances, you may request that we restrict the processing of your personal information."),
                .paragraph("9.8 Right to Object (GDPR Art. 21): You may object to processing based on our legitimate interests. We will cease processing unless we demonstrate compelling legitimate grounds."),
                .paragraph("9.9 How to Exercise Your Rights: To exercise any of these rights, contact us at privacy@eusorone.com or through the Privacy Settings in your account. We will respond to verified requests within 45 days (CCPA) or 30 days (GDPR/VCDPA). We may extend the response period by an additional 45 days (CCPA) or 60 days (GDPR) if reasonably necessary, with notice."),
                .paragraph("9.10 Authorized Agents: You may designate an authorized agent to submit privacy requests on your behalf with proper written authorization."),
                .paragraph("9.11 Appeal: If we deny your privacy request, you have the right to appeal by contacting us at privacy@eusorone.com. If your appeal is denied, you may contact your state's Attorney General.")
            ]
        ),
        Section(
            id: "location-data",
            title: "10. Location Data & GPS Tracking",
            sfSymbol: "location.fill",
            iconTint: Color.red400,
            highlight: false,
            blocks: [
                .paragraph("10.1 When We Collect Location Data: We collect GPS location data from Drivers and vehicles: (a) during active load assignments (from acceptance to delivery confirmation); (b) when ELD-equipped vehicles are in operation (as required by 49 CFR Part 395); (c) when you voluntarily enable location sharing for features like nearby load search or rest stop finder."),
                .paragraph("10.2 How We Use Location Data: Location data is used for: real-time load tracking and ETA updates; ELD/HOS compliance; geofence alerts for pickup/delivery; route optimization; emergency response coordination; verifying load completion and proof of delivery; detention time calculation."),
                .paragraph("10.3 Who Sees Your Location: Your real-time location during active loads is visible to: the Shipper, Broker, and/or Dispatcher associated with the active load; your catalyst's fleet management team; Platform safety and compliance systems. Your location is NOT visible to other unrelated Platform Users."),
                .paragraph("10.4 Controlling Location Data: Location tracking during active ELD operation is required by federal regulation and cannot be disabled. For non-ELD location features, you may disable location permissions in your device settings. Disabling location may limit certain Platform features.")
            ]
        ),
        Section(
            id: "children",
            title: "11. Children's Privacy",
            sfSymbol: "figure.child",
            iconTint: Color.pink400,
            highlight: false,
            blocks: [
                .paragraph("The Platform is not intended for use by individuals under the age of 18. We do not knowingly collect personal information from children under 18 (or under 16 for GDPR purposes). If you are under 18, you may not create an account or use the Platform."),
                .paragraph("If we become aware that we have collected personal information from a child under the applicable age, we will take steps to delete such information promptly. If you believe we have inadvertently collected information from a minor, please contact us immediately at privacy@eusorone.com.")
            ]
        ),
        Section(
            id: "international",
            title: "12. International Data Transfers",
            sfSymbol: "globe",
            iconTint: Color.teal400,
            highlight: false,
            blocks: [
                .paragraph("The Platform is primarily operated in the United States. Your information may be transferred to, stored in, and processed in the United States and other countries where our service providers operate."),
                .paragraph("If you are accessing the Platform from outside the United States, please be aware that your information will be transferred to the United States, which may have different data protection laws than your country. By using the Platform, you consent to this transfer."),
                .paragraph("For transfers of personal data from the EU/EEA, we rely on: (a) Standard Contractual Clauses (SCCs) approved by the European Commission; (b) data processing agreements with all service providers; and (c) additional technical and organizational safeguards to ensure adequate protection of your data.")
            ]
        ),
        Section(
            id: "state-specific",
            title: "13. State-Specific Disclosures",
            sfSymbol: "doc.text.fill",
            iconTint: Color.violet400,
            highlight: false,
            blocks: [
                .emphasized("13.1 California Residents (CCPA/CPRA):"),
                .bullets([
                    "Categories of personal information collected: Identifiers, commercial information, internet activity, geolocation data, professional/employment information, biometric information (if fingerprint/facial verification is used), financial information",
                    "Business purposes for collection: As described in Section 3",
                    "Categories of third parties with whom information is shared: As described in Section 5",
                    "We do not sell or share (as defined by CPRA) personal information for cross-context behavioral advertising",
                    "We do not use or disclose sensitive personal information for purposes other than those permitted by CCPA 1798.121",
                    "Financial incentive programs (e.g., gamification rewards, referral bonuses) are based on Platform usage and are not tied to the value of your personal information"
                ]),
                .paragraph("13.2 Texas Residents (TDPSA): Texas residents have the right to access, correct, delete, and obtain a copy of their personal data, and to opt out of targeted advertising, sale, and profiling. Contact us at privacy@eusorone.com to exercise these rights."),
                .paragraph("13.3 Virginia, Colorado, Connecticut Residents: Residents of these states have similar rights under VCDPA, CPA, and CTDPA respectively. Contact us at privacy@eusorone.com to exercise your rights. You may appeal any denial to us, and if unsatisfied, to your state Attorney General.")
            ]
        ),
        Section(
            id: "changes",
            title: "14. Changes to This Privacy Policy",
            sfSymbol: "arrow.clockwise",
            iconTint: Color.slate400,
            highlight: false,
            blocks: [
                .paragraph("We may update this Privacy Policy from time to time to reflect changes in our practices, technologies, legal requirements, or other factors. When we make material changes, we will:"),
                .bullets([
                    "Update the \"Last Updated\" date at the top of this page",
                    "Provide notice through the Platform (in-app notification or banner)",
                    "Send an email notification to your registered email address for material changes",
                    "Where required by law, obtain your consent before implementing changes"
                ]),
                .paragraph("Your continued use of the Platform after we post changes constitutes your acceptance of the updated Privacy Policy. We encourage you to review this Privacy Policy periodically.")
            ]
        ),
        Section(
            id: "contact",
            title: "15. Contact Us & Data Protection Officer",
            sfSymbol: "envelope.fill",
            iconTint: Color.blue400,
            highlight: false,
            blocks: [
                .paragraph("If you have questions, concerns, or requests regarding this Privacy Policy or our data practices, please contact us:"),
                .emphasized("Data Protection Officer"),
                .paragraph("Eusorone Technologies Inc. · privacy@eusorone.com"),
                .emphasized("Legal Department"),
                .paragraph("Eusorone Technologies Inc. · legal@eusorone.com"),
                .paragraph("If you are not satisfied with our response, you have the right to lodge a complaint with your applicable data protection authority or state Attorney General.")
            ]
        )
    ]
}

// MARK: - Tailwind-style emerald tokens (used by Privacy banner)

extension Color {
    static let emerald300 = Color(hex: 0x6EE7B7)
    static let emerald400 = Color(hex: 0x34D399)
}

// MARK: - Previews (Dark + Light)

#Preview("Privacy · Dark") {
    PrivacyPolicyView()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("Privacy · Light") {
    PrivacyPolicyView()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
