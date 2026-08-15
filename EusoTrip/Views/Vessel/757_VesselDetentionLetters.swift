//
//  757_VesselDetentionLetters.swift
//  EusoTrip — Vessel Operator · Detention Letters.
//
//  Faithful port of "757 Vessel Detention Letters.svg" (Light + Dark, 2026-06-25 reconstruction),
//  RECONSTRUCTED to flagship CORRESPONDENCE grammar (mirror 02 Shipper/205 + 06 Vessel/758):
//  28pt detail title + caption + overflow, EXPOSURE gradient-rim hero (total pending detention
//  figure + INITIAL/ESCALATION/FINAL tier chips), a facility letter ledger where every card carries
//  a 40x40 tier-color letter chip + facility title + NOTICE-id mono sub + tier pill + events/charges/
//  wait line + Review chip + date, CTA pair (Generate letters / Export PDF), ESang chronic-facility
//  row, and the COUNTRY-DONE 2026-06-25 NOTICE-REGIME footer (segmented US active · CA · MX) citing
//  each notice's governing authority + statutory dispute window by facility port country —
//  US FMC/OSRA 49 CFR 30-day · CA CTA carrier tariff · MX SAT-Aduanas recinto + Profeco. Reference/
//  citation affordance only — no new mutation, no fabricated CA/MX rows; distinct segmented geometry
//  vs 788. Registered type name kept (VesselDetentionLettersScreen · ContentView "Vesl757").
//
//  Data / wiring (endpoints re-verified on disk this fire):
//    detentionAccessorials.getDetentionLetters (EXISTS frontend/server/routers/detentionAccessorials.ts:1652 ·
//      input {facilityName?,dateFrom?,dateTo?}? · returns {letters:[{facilityName,eventCount,totalCharges,
//      avgWaitMinutes,firstEvent,lastEvent,letterType final_warning|escalation|initial_notice,status:"draft"}]}
//      grouped from detention_claims HAVING event_count>=2, ORDER BY total_charges DESC LIMIT 20).
//    "Review" chip → in-place detail sheet built from the loaded letter row (real fetched fields —
//      events, charges, wait, event window, tier, cited regime). Real local effect, zero dead taps.
//    "Export PDF" → REAL on-device render: ImageRenderer → CGContext PDF of the loaded ledger,
//      shared via ShareLink. No fabricated figures — the document is the live return, papered.
//    "Generate letters" → detentionAccessorials.createDetentionLetter (EXISTS) persists one draft
//      demand letter per loaded facility with real event/charge/window fields, then surfaces saved
//      evidence without claiming the letter was issued.
//    Named-gap #2: getDetentionLetters rows carry no portCode (UN/LOCODE) — the regime footer's
//      active segment derivation falls back to US until the row carries the real port country.
//
//  0 mock data on load · honest empty/error states — values render only from the live return; empty
//  ledger shows the bespoke empty state. No raw transport error text reaches user copy.
//

import SwiftUI

private enum LetterTier757 { case initialNotice, escalation, finalNotice
    var label: String { switch self { case .initialNotice: "INITIAL NOTICE"; case .escalation: "ESCALATION"; case .finalNotice: "FINAL NOTICE" } }
    var tint: Color { switch self { case .initialNotice: Color(red: 0.08, green: 0.40, blue: 0.75); case .escalation: Color(red: 0.70, green: 0.45, blue: 0.0); case .finalNotice: Color(red: 0.78, green: 0.16, blue: 0.16) } }
}

private struct FacilityLetter757: Identifiable {
    let id = UUID()
    let facility: String
    let notice: String
    let tier: LetterTier757
    let letterTypeRaw: String
    let events: Int
    let totalChargesValue: Double
    let charges: String
    let avgWaitMinutesValue: Int
    let avgWait: String
    let status: String
    let date: String          // last event date (real, from lastEvent)
    let window: String        // first → last event window (real)
    let firstEventRaw: String?
    let lastEventRaw: String?
}

struct VesselDetentionLettersScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselDetentionLettersBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct PdfExport757: Identifiable {
    let id = UUID()
    let url: URL
}

private struct VesselDetentionLettersBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadFailed = false
    @State private var hasLetters = false

    @State private var exposure = "$0"
    @State private var exposureSub = "across 0 events"
    @State private var avgWait = "no detention to paper"
    @State private var nInitial = 0
    @State private var nEscalation = 0
    @State private var nFinal = 0

    @State private var letters: [FacilityLetter757] = []

    // Review drill-down, PDF export, persisted draft-letter generation.
    @State private var reviewLetter: FacilityLetter757? = nil
    @State private var pdfExport: PdfExport757? = nil
    @State private var generatingLetters = false
    @State private var generatedLetterIds: [String] = []
    @State private var generateFailed = false
    @State private var generateMessage: String? = nil
    @State private var exportFailed = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if loadFailed {
                    LifecycleCard(accentDanger: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("The detention ledger didn't load.").font(EType.caption).foregroundStyle(Brand.danger)
                            Text("Check your connection — recorded detention events are safe and reload on refresh.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                            Button { Task { await load() } } label: {
                                Text("Retry").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.blue)
                            }.buttonStyle(.plain)
                        }
                    }
                } else if !hasLetters {
                    EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                                   title: "No detention letters to paper",
                                   subtitle: "No facility has two or more detention events in range — there is nothing to escalate.")
                } else {
                    exposureHero
                    Text("BY FACILITY · WORST OFFENDERS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    ForEach(letters) { facilityCard($0) }
                    HStack(spacing: 8) {
                        CTAButton(
                            title: generateCtaTitle,
                            action: { Task { await generateLetters() } },
                            trailingIcon: "doc.badge.plus",
                            isLoading: generatingLetters || allDraftsGenerated
                        )
                        secondaryButton(title: "Export PDF") { exportPdf() }
                    }
                    if let generateMessage { generateResultCard(message: generateMessage, failed: generateFailed) }
                    if exportFailed {
                        Text("The PDF didn't render on this device. The ledger above stays live — try the export again.")
                            .font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    ESangRow757(title: "ESang: \(chronicFacility) is your chronic offender",
                                subtitle: chronicSubtitle)
                    regimeFooter
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .sheet(item: $reviewLetter) { letter in
            LetterReviewSheet757(letter: letter, regime: regimeCitation(for: letter))
        }
        .sheet(item: $pdfExport) { export in
            LetterPdfShareSheet757(url: export.url)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · DETENTION LETTERS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("3 TIERS").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Notice letters").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var exposureHero: some View {
        RimCard757 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("PENDING DETENTION · \(letters.count) \(letters.count == 1 ? "FACILITY" : "FACILITIES")").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("QTD").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(exposure).font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exposureSub).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(avgWait).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    tierChip(count: nInitial, label: "INITIAL", tint: LetterTier757.initialNotice.tint)
                    tierChip(count: nEscalation, label: "ESCALATION", tint: LetterTier757.escalation.tint)
                    tierChip(count: nFinal, label: "FINAL", tint: LetterTier757.finalNotice.tint)
                }
            }
        }
    }

    private func tierChip(count: Int, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            ZStack { Circle().fill(tint).frame(width: 12, height: 12)
                Text("\(count)").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white) }
            Text(label).font(.system(size: 10, weight: .bold)).tracking(0.4).foregroundStyle(tint)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.12)))
        .frame(maxWidth: .infinity)
    }

    private func facilityCard(_ l: FacilityLetter757) -> some View {
        LifecycleCard {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(l.tier.tint.opacity(0.12)).frame(width: 40, height: 40)
                    .overlay(Image(systemName: "doc.text").font(.system(size: 16, weight: .semibold)).foregroundStyle(l.tier.tint))
                VStack(alignment: .leading, spacing: 6) {
                    Text(l.facility).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(l.notice).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    Text(l.tier.label).font(.system(size: 10, weight: .heavy)).tracking(0.4).foregroundStyle(l.tier.tint)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(l.tier.tint.opacity(0.12)))
                    Text("\(l.events) events · \(l.charges) charges · avg wait \(l.avgWait)").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text(l.status).font(.system(size: 11, weight: .bold)).tracking(0.4).foregroundStyle(palette.textTertiary)
                    secondaryButton(title: "Review") { reviewLetter = l }
                        .frame(width: 84, height: 28)
                    Text(l.date).font(.system(size: 11)).monospacedDigit().foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var allDraftsGenerated: Bool {
        !letters.isEmpty && generatedLetterIds.count >= letters.count
    }

    private var generateCtaTitle: String {
        if generatingLetters { return "Generating…" }
        if allDraftsGenerated { return "\(generatedLetterIds.count) drafts saved" }
        return "Generate letters"
    }

    private func generateResultCard(message: String, failed: Bool) -> some View {
        LifecycleCard(accentWarning: failed) {
            VStack(alignment: .leading, spacing: 6) {
                Text(failed ? "Some drafts did not save" : "Draft letters saved")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(failed ? Brand.danger : palette.textPrimary)
                Text(message)
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                Button { withAnimation(.easeOut(duration: 0.12)) { generateMessage = nil; generateFailed = false } } label: {
                    Text("Dismiss").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.blue)
                }.buttonStyle(.plain)
            }
        }
    }

    /// Bespoke secondary (outline) button — same outline grammar the registered
    /// siblings (680) use for their secondary CTA.
    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    /// Chronic offender for the ESang row = worst facility (the return orders by
    /// total_charges DESC, so the first letter is the highest-exposure facility).
    private var chronicFacility: String { letters.first?.facility ?? "-" }
    private var chronicSubtitle: String {
        guard let top = letters.first else { return "send the final notice now" }
        let verb = (top.tier == .finalNotice) ? "send the final notice now" : "escalate now"
        return "\(verb) - \(top.events) events, \(top.charges) unpapered"
    }

    // ── Notice regime · the authority + statutory dispute window each notice cites,
    // by port country. The letters return carries no portCode (UN/LOCODE) — named gap —
    // so the active segment falls back to US (all papered facilities are US ports today).
    private var portCountries: Set<String> { ["US"] }

    private var regimeFooter: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("NOTICE REGIME · AUTHORITY BY PORT COUNTRY").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("auto-cited").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
                HStack(spacing: 6) {
                    regimeSegment(code: "US", authority: "FMC OSRA · 30d", active: portCountries.contains("US"))
                    regimeSegment(code: "CA", authority: "CTA tariff",      active: portCountries.contains("CA"))
                    regimeSegment(code: "MX", authority: "SAT · Profeco",   active: portCountries.contains("MX"))
                }
            }
        }
    }

    private func regimeSegment(code: String, authority: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Text(code).font(.system(size: 10, weight: .heavy))
            Text(authority).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(active ? Color.white : palette.textSecondary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(active ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary.opacity(0.12)))
        )
    }

    private func regimeCitation(for letter: FacilityLetter757) -> String {
        // Falls back to the US regime until the letters row carries a real port country.
        "US · FMC OSRA 49 CFR — 30-day billing-dispute window"
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadFailed = false
        do {
            struct Letter: Decodable {
                let facilityName: String?; let eventCount: Int?; let totalCharges: Double?
                let avgWaitMinutes: Int?; let letterType: String?; let status: String?
                let firstEvent: String?; let lastEvent: String?
            }
            struct Resp: Decodable { let letters: [Letter]? }
            let r: Resp = try await EusoTripAPI.shared.query("detentionAccessorials.getDetentionLetters", input: EmptyInput757())
            if let ls = r.letters, !ls.isEmpty {
                var totalCharges = 0.0, totalEvents = 0, totalWait = 0, ini = 0, esc = 0, fin = 0
                letters = ls.map { l in
                    let tier: LetterTier757 = (l.letterType == "final_warning") ? .finalNotice : (l.letterType == "escalation" ? .escalation : .initialNotice)
                    switch tier { case .initialNotice: ini += 1; case .escalation: esc += 1; case .finalNotice: fin += 1 }
                    totalCharges += l.totalCharges ?? 0
                    totalEvents += l.eventCount ?? 0
                    totalWait += l.avgWaitMinutes ?? 0
                    let wait = Double(l.avgWaitMinutes ?? 0) / 60.0
                    return FacilityLetter757(
                        facility: l.facilityName ?? "-",
                        notice: "NOTICE · \(l.facilityName?.prefix(3).uppercased() ?? "-")",
                        tier: tier,
                        letterTypeRaw: l.letterType ?? "initial_notice",
                        events: l.eventCount ?? 0,
                        totalChargesValue: l.totalCharges ?? 0,
                        charges: "$\(Int(l.totalCharges ?? 0))",
                        avgWaitMinutesValue: l.avgWaitMinutes ?? 0,
                        avgWait: String(format: "%.1fh", wait),
                        status: (l.status ?? "draft").uppercased(),
                        date: Self.shortDate(l.lastEvent),
                        window: "\(Self.shortDate(l.firstEvent)) → \(Self.shortDate(l.lastEvent))",
                        firstEventRaw: l.firstEvent,
                        lastEventRaw: l.lastEvent)
                }
                exposure = "$\(Int(totalCharges))"
                exposureSub = "across \(totalEvents) events"
                let avgHours = Double(totalWait) / Double(ls.count) / 60.0
                avgWait = String(format: "avg wait %.1fh · ready to paper", avgHours)
                nInitial = ini; nEscalation = esc; nFinal = fin
                hasLetters = true
            } else {
                letters = []; hasLetters = false
            }
        } catch {
            // Doctrine: no raw transport error text in user copy — the error card
            // carries the user-grammar message.
            loadFailed = true
        }
        loading = false
    }

    @MainActor private func generateLetters() async {
        guard !generatingLetters, !letters.isEmpty, !allDraftsGenerated else { return }
        generatingLetters = true
        generateFailed = false
        generateMessage = nil

        struct CreateInput757: Encodable {
            let facilityName: String
            let portCode: String?
            let letterType: String
            let eventCount: Int
            let totalCharges: Double
            let avgWaitMinutes: Int?
            let periodFrom: String?
            let periodTo: String?
            let body: String?
        }
        struct CreateResp757: Decodable {
            let success: Bool?
            let id: Int?
            let letterId: String?
        }

        var saved: [String] = []
        do {
            for letter in letters {
                let input = CreateInput757(
                    facilityName: letter.facility,
                    portCode: nil,
                    letterType: letter.letterTypeRaw,
                    eventCount: letter.events,
                    totalCharges: letter.totalChargesValue,
                    avgWaitMinutes: letter.avgWaitMinutesValue,
                    periodFrom: letter.firstEventRaw,
                    periodTo: letter.lastEventRaw,
                    body: demandLetterBody(for: letter)
                )
                let result: CreateResp757 = try await EusoTripAPI.shared.mutation(
                    "detentionAccessorials.createDetentionLetter",
                    input: input
                )
                let savedId = result.letterId ?? result.id.map { "dl_\($0)" } ?? letter.notice
                saved.append(savedId)
            }
            generatedLetterIds = saved
            generateMessage = "\(saved.count) draft \(saved.count == 1 ? "letter is" : "letters are") now saved for review, issue, acknowledgement, payment, or dispute."
        } catch {
            generateFailed = true
            generateMessage = "No charge figures were changed. Retry when the connection recovers or reopen the screen to confirm whether any partial draft saved."
        }
        generatingLetters = false
    }

    private func demandLetterBody(for letter: FacilityLetter757) -> String {
        """
        Detention notice draft
        Facility: \(letter.facility)
        Tier: \(letter.tier.label)
        Events: \(letter.events)
        Charges: \(letter.charges)
        Average wait: \(letter.avgWait)
        Event window: \(letter.window)
        Regime: \(regimeCitation(for: letter))
        """
    }

    /// "2026-04-28T09:12:33.000Z" / "2026-04-28 09:12:33" → "Apr 28" (falls back to the raw day).
    private static func shortDate(_ raw: String?) -> String {
        guard let raw, raw.count >= 10 else { return "-" }
        let day = String(raw.prefix(10))
        let inFmt = DateFormatter(); inFmt.dateFormat = "yyyy-MM-dd"; inFmt.locale = Locale(identifier: "en_US_POSIX")
        guard let d = inFmt.date(from: day) else { return day }
        let outFmt = DateFormatter(); outFmt.dateFormat = "MMM d"; outFmt.locale = Locale(identifier: "en_US_POSIX")
        return outFmt.string(from: d)
    }

    // MARK: - Export PDF (real on-device render of the loaded ledger)

    @MainActor private func exportPdf() {
        exportFailed = false
        let doc = DetentionLetterPrintView757(
            exposure: exposure, exposureSub: exposureSub,
            nInitial: nInitial, nEscalation: nEscalation, nFinal: nFinal,
            letters: letters)
        let renderer = ImageRenderer(content: doc.frame(width: 612))
        renderer.proposedSize = ProposedViewSize(width: 612, height: nil)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EusoTrip-Detention-Letters.pdf")
        var rendered = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: CGSize(width: 612, height: max(size.height, 792)))
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            rendered = true
        }
        if rendered {
            pdfExport = PdfExport757(url: url)
        } else {
            exportFailed = true
        }
    }
}

// MARK: - Review sheet (real fetched letter fields — no new network round-trip)

private struct LetterReviewSheet757: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let letter: FacilityLetter757
    let regime: String

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack {
                    Text(letter.tier.label).font(.system(size: 10, weight: .heavy)).tracking(0.4).foregroundStyle(letter.tier.tint)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(letter.tier.tint.opacity(0.12)))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(palette.textTertiary)
                    }.buttonStyle(.plain)
                }
                Text(letter.facility).font(.system(size: 24, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(letter.notice).font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.textSecondary)
                IridescentHairline()
                detailRow("Detention events", "\(letter.events)")
                detailRow("Charges accrued", letter.charges)
                detailRow("Average wait", letter.avgWait)
                detailRow("Event window", letter.window)
                detailRow("Letter status", letter.status)
                LifecycleCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GOVERNING REGIME").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        Text(regime).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .background(palette.bgPage.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func detailRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(v).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - PDF share sheet

private struct LetterPdfShareSheet757: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        VStack(spacing: Space.s4) {
            Image(systemName: "doc.richtext").font(.system(size: 34, weight: .semibold)).foregroundStyle(LinearGradient.diagonal)
            Text("Detention letter pack is ready").font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("The PDF carries the live exposure figure and every facility ledger row.")
                .font(EType.caption).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
            ShareLink(item: url) {
                Text("Share PDF")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Button { dismiss() } label: {
                Text("Done").font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.blue)
            }.buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bgPage.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

// MARK: - Printable ledger (document styling — renders the live return verbatim)

private struct DetentionLetterPrintView757: View {
    let exposure: String
    let exposureSub: String
    let nInitial: Int
    let nEscalation: Int
    let nFinal: Int
    let letters: [FacilityLetter757]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("EusoTrip · Detention letter pack")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(.black)
            Text("Pending detention exposure: \(exposure) · \(exposureSub)")
                .font(.system(size: 13)).foregroundStyle(.black)
            Text("Tiers: \(nInitial) initial notice · \(nEscalation) escalation · \(nFinal) final notice")
                .font(.system(size: 11)).foregroundStyle(Color(white: 0.25))
            Rectangle().fill(Color(white: 0.8)).frame(height: 1)
            ForEach(letters) { l in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(l.facility) — \(l.tier.label)")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                    Text("\(l.notice) · \(l.events) events · \(l.charges) charges · avg wait \(l.avgWait)")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(white: 0.2))
                    Text("Event window \(l.window) · status \(l.status)")
                        .font(.system(size: 11)).foregroundStyle(Color(white: 0.35))
                }
                .padding(.bottom, 6)
            }
            Text("Cited regime: US FMC OSRA 49 CFR — 30-day billing-dispute window.")
                .font(.system(size: 10)).foregroundStyle(Color(white: 0.35))
        }
        .padding(36)
        .frame(width: 612, alignment: .leading)
        .background(Color.white)
    }
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// Gradient-rim hero card — mirrors the gradient-stroked context cards the
/// registered siblings (664 `moveContextCard`, 680 `shipmentContextCard`) ship.
private struct RimCard757<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
    }
}

/// ESang advisory row — sparkle + advisory grammar, file-scoped.
private struct ESangRow757: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }
}

private struct EmptyInput757: Encodable {}

#Preview("757 · Detention Letters · Night") { VesselDetentionLettersScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("757 · Detention Letters · Light") { VesselDetentionLettersScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
