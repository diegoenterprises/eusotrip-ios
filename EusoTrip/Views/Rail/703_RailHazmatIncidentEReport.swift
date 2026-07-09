//
//  703_RailHazmatIncidentEReport.swift
//  EusoTrip — Rail Engineer · Hazmat Incident E-Report (49 CFR 171.16 PHMSA
//  filing gate). Distinct from 631 FRA Accident Reports (FRA 6180.54) and
//  597 Hazmat DG Rules reference — 703 drives the regulatory clock after a
//  hazardous-materials release.
//
//  Bespoke port of "05 Rail/Light-SVG/703 Rail Hazmat Incident E-Report.svg" (+ Dark).
//  ARCHETYPE = INCIDENT-FILING GATE — severity-verdict hero (release + NRC
//  notification clock), two-step filing gate (Step 1 NRC telephonic immediate,
//  Step 2 DOT Form 5800.1 written · 30-day), incident-facts card carrying the
//  49 CFR 171.16 field set: UN/NA number · proper shipping name · quantity
//  released · packaging · cause.
//
//  Role: RAIL_ENGINEER (compliance). transportMode=rail. Hazmat is the most
//  stringent lens — no field on this surface is ever fabricated.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getRailInspections   EXISTS:1915 {limit} → failed
//        hazmat-flavored rows are the REAL incident-context feed.
//    railShipments.getRailHazmatPermits EXISTS:1946 {limit} →
//        [{id,permitNumber,commodity,expiresAt,status}] — UN/commodity context.
//  REAL device action:
//    "Call emergency line" dials the regime's real emergency number via the
//    system dialer — US NRC 1-800-424-8802 · CA CANUTEC 1-888-226-8832 ·
//    MX SETIQ 800-00-214-00.
//    railHazmat.logNrcNotification — records the call confirmation.
//    railHazmat.fileIncidentReport (irreversible regulatory filing) — the
//    written 5800.1 is submitted via this mutation.
//

import SwiftUI

struct RailHazmatIncidentReportScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            RailHazmatIncidentReportBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct InspectionRow703: Decodable {
    let id: String?
    let type: String?
    let date: String?
    let location: String?
    let status: String?
    let inspector: String?
    let notes: String?
    let passed: Bool?
}

private struct HazmatPermitRow703: Decodable {
    let id: String?
    let permitNumber: String?
    let commodity: String?
    let expiresAt: String?
    let status: String?
}

private struct LimitInput703: Encodable { let limit: Int }

/// One filed 49 CFR 171.16 incident off `railHazmat.getIncidentReports`.
private struct IncidentReportRow703: Decodable, Identifiable {
    let id: String
    let railcarNumber: String?
    let unNumber: String?
    let incidentType: String?
    let cfrRef: String?
    let location: String?
    let description: String?
    let nrcNotified: Bool?
    let nrcNotificationNumber: String?
    let filedAt: String?
}
private struct IncidentReportsInput703: Encodable { let limit: Int }
private struct FileIncidentInput703: Encodable {
    let confirm: Bool
    let railcarNumber: String?
    let unNumber: String?
    let incidentType: String
    let location: String?
    let description: String
}
private struct FileIncidentResult703: Decodable { let success: Bool?; let id: Int?; let incidentId: String? }
private struct LogNrcInput703: Encodable { let incidentId: Int; let notificationNumber: String }
private struct LogNrcResult703: Decodable { let success: Bool? }

/// The 49 CFR 171.16 incident-facts field set. Every value comes off the
/// real records; a field with no source value reads "Not captured".
private struct IncidentFacts703 {
    var unNumber: String?
    var shippingName: String?
    var quantityReleased: String?
    var packaging: String?
    var cause: String?

    var rows: [(label: String, value: String, captured: Bool, mono: Bool)] {
        [("UN / NA number",       unNumber ?? "Not captured",         unNumber != nil,         true),
         ("Proper shipping name", shippingName ?? "Not captured",     shippingName != nil,     false),
         ("Quantity released",    quantityReleased ?? "Not captured", quantityReleased != nil, false),
         ("Packaging",            packaging ?? "Not captured",        packaging != nil,        false),
         ("Cause",                cause ?? "Not captured",            cause != nil,            false)]
    }
}

// MARK: - Body

private struct RailHazmatIncidentReportBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @State private var inspections: [InspectionRow703] = []
    @State private var permits: [HazmatPermitRow703] = []
    @State private var incidents: [IncidentReportRow703] = []
    @State private var loading = true
    @State private var regime = 0
    @State private var showFileNotice = false
    @State private var showRecordConfirm = false
    @State private var filing = false
    @State private var fileMessage: String? = nil
    // NRC call logging (per filed incident).
    @State private var nrcTargetId: Int? = nil
    @State private var nrcNumber: String = ""
    @State private var showNrcSheet = false

    /// Regime → (band label, band caption, emergency-line name, dial string).
    private let regimes: [(String, String, String, String)] = [
        ("US · PHMSA", "171.16 · NRC",  "NRC",     "18004248802"),
        ("CA · TDG",   "CANUTEC",       "CANUTEC", "18882268832"),
        ("MX · SCT",   "NOM-002",       "SETIQ",   "8000021400"),
    ]

    /// The incident context: the most recent FAILED hazmat-flavored
    /// inspection on file. No failed hazmat row → no incident → honest empty.
    private var incident: InspectionRow703? {
        inspections
            .filter { $0.passed == false && Self.isHazmatFlavored($0) }
            .sorted { (Self.date($0.date) ?? .distantPast) > (Self.date($1.date) ?? .distantPast) }
            .first
    }

    /// Active hazmat permit — the UN/commodity context feed.
    private var activePermit: HazmatPermitRow703? {
        permits.first { ($0.status ?? "").lowercased() == "active" } ?? permits.first
    }

    private var lastFiledReport: IncidentReportRow703? {
        incidents.sorted { (Self.date($0.filedAt) ?? .distantPast) > (Self.date($1.filedAt) ?? .distantPast) }.first
    }

    private var facts: IncidentFacts703 {
        var f = IncidentFacts703()
        let notes = incident?.notes ?? ""
        // UN number — off the real notes or the real permit commodity string.
        f.unNumber = Self.firstMatch(#"UN\s?(\d{4})"#, in: notes).map { "UN\($0)" }
            ?? Self.firstMatch(#"UN\s?(\d{4})"#, in: activePermit?.commodity ?? "").map { "UN\($0)" }
        // Shipping name — the permit's real commodity classes when present.
        if let commodity = activePermit?.commodity, !commodity.isEmpty {
            f.shippingName = commodity
        }
        // Quantity / packaging / cause parse only from real notes text.
        f.quantityReleased = Self.firstMatch(#"(\d+(?:\.\d+)?\s*(?:gal|gallons|l|liters|lbs?|kg))"#, in: notes)
        if notes.lowercased().contains("tank") { f.packaging = "Tank car" }
        if let causeRange = notes.range(of: "cause:", options: .caseInsensitive) {
            f.cause = String(notes[causeRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else if !notes.isEmpty {
            f.cause = notes
        }
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Hazmat incident")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text(subtitleLine)
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else if incident == nil {
                    EusoEmptyState(systemImage: "checkmark.shield",
                                   title: "No hazmat incident on file",
                                   subtitle: "A reportable release opens this filing gate the moment a failed hazmat inspection is recorded. Nothing on file requires a 49 CFR 171.16 report.")
                    triBand
                    emergencyLineCard
                } else {
                    severityHero
                    gateHeader
                    filingGate
                    factsHeader
                    factsCard
                    triBand
                    footerActions
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Written report can't be filed from this device", isPresented: $showFileNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("EusoTrip can't submit the written DOT Form 5800.1 for this incident. The immediate telephonic notification still works — dial the emergency line below, and file the written report with PHMSA within 30 days of the release.")
        }
        .alert("File a 49 CFR 171.16 incident record?", isPresented: $showRecordConfirm) {
            Button("File incident", role: .destructive) { Task { await fileIncident() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This creates a permanent, immutable incident record for the flagged hazmat car. It can't be edited or removed after filing. Confirm the details are correct.")
        }
        .sheet(isPresented: $showNrcSheet) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Log NRC notification").font(EType.h2).foregroundStyle(palette.textPrimary)
                Text("Enter the National Response Center case number from your telephonic notification. This is recorded once and can't be changed.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                TextField("NRC case number", text: $nrcNumber)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(Space.s3).background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                CTAButton(title: "Record NRC reference", action: { Task { await logNrc() } })
                    .disabled(nrcNumber.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
            .padding(20).presentationDetents([.height(280)]).presentationDragIndicator(.visible)
            .background(palette.bgPage)
        }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            Text("✦ RAIL ENGINEER · HAZMAT INCIDENT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("49 CFR 171.16")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var subtitleLine: String {
        if let i = incident {
            var bits: [String] = []
            if let un = facts.unNumber { bits.append(un) }
            if let loc = i.location, !loc.isEmpty { bits.append(loc) }
            if let d = Self.date(i.date) { bits.append("recorded \(Self.shortLabel(d))") }
            return bits.isEmpty ? "Reportable release on file" : bits.joined(separator: " · ")
        }
        return "PHMSA hazardous-materials incident filing"
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            if incident != nil {
                chip("REPORTABLE", Brand.danger)
                chip("call unconfirmed", Brand.warning)
                if let un = facts.unNumber { chip(un, Brand.hazmat) }
            } else {
                chip("no incident", Brand.success)
                chip("filing gate idle", palette.textSecondary)
            }
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Severity hero — release quantity (real or "not captured") +
    // NRC clock. The clock NEVER reads "notified" without a recorded call
    // confirmation — and none exists on file.

    private var severityHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HAZMAT INCIDENT · REPORTABLE · 49 CFR 171.16")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(Brand.danger)
                Spacer()
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [Brand.danger.opacity(0.14), Brand.warning.opacity(0.10)],
                                       startPoint: .leading, endPoint: .trailing))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(facts.quantityReleased ?? "Quantity not captured")
                            .font(.system(size: facts.quantityReleased == nil ? 18 : 30, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        if facts.quantityReleased != nil {
                            Text("released")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    Text(subtitleLine)
                        .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(regimes[regime].2) CALL")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text(lastFiledReport?.nrcNotificationNumber ?? "—")
                        .font(.system(size: 16, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(lastFiledReport?.nrcNotified == true ? Brand.success : Brand.warning)
                    Text(lastFiledReport?.nrcNotified == true ? "notified" : "awaiting call confirmation")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(lastFiledReport?.nrcNotified == true ? Brand.success : Brand.warning)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var gateHeader: some View {
        HStack {
            Text("FILING GATE · TWO STEPS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("PHMSA")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var filingGate: some View {
        let filed = lastFiledReport != nil
        let notified = lastFiledReport?.nrcNotified == true
        return VStack(spacing: 0) {
            gateRow(step: "1",
                    title: "\(regimes[regime].2) telephonic notification",
                    caption: notified ? "Logged: \(lastFiledReport?.nrcNotificationNumber ?? "")" : "\(dialDisplay) · immediate",
                    status: notified ? "NOTIFIED" : "AWAITING CONFIRMATION",
                    color: notified ? Brand.success : Brand.warning,
                    done: notified)
            Divider().overlay(palette.borderFaint)
            gateRow(step: "2",
                    title: "DOT Form 5800.1 written",
                    caption: "detailed incident report · due within 30 days of release",
                    status: filed ? "FILED" : "NOT FILED",
                    color: filed ? Brand.success : Brand.danger,
                    done: filed)
        }
        .padding(.horizontal, 16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func gateRow(step: String, title: String, caption: String,
                         status: String, color: Color, done: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.14)).frame(width: 30, height: 30)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .heavy)).foregroundStyle(color)
                } else {
                    Text(step).font(.system(size: 13, weight: .heavy)).foregroundStyle(color)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(caption)
                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(status)
                .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
    }

    private var factsHeader: some View {
        HStack {
            Text("INCIDENT FACTS · 49 CFR 171.16")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("from records on file")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var factsCard: some View {
        VStack(spacing: 0) {
            let rows = facts.rows
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack(alignment: .top) {
                    Text(r.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(r.value)
                        .font(.system(size: 11.5, weight: .bold,
                                      design: r.mono && r.captured ? .monospaced : .default))
                        .foregroundStyle(r.captured ? palette.textPrimary : palette.textTertiary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 10)
                if i < rows.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(.horizontal, 16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// Standing emergency-line card for the no-incident state — the dial
    /// action stays reachable even when the filing gate is idle.
    private var emergencyLineCard: some View {
        Button(action: dial) {
            HStack(spacing: 12) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Brand.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(regimes[regime].2) emergency line")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text(dialDisplay)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(16)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var triBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == regime ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == regime ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { regime = i }
            }
        }
    }

    @ViewBuilder
    private var footerActions: some View {
        if let m = fileMessage {
            Text(m).font(EType.caption).foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if !incidents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("FILED 171.16 INCIDENTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                ForEach(incidents.prefix(4)) { inc in
                    HStack(spacing: 8) {
                        Circle().fill(inc.nrcNotified == true ? Brand.success : Brand.warning).frame(width: 7, height: 7)
                        Text([inc.railcarNumber, inc.unNumber.map { "UN\($0)" }, inc.incidentType].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textSecondary).lineLimit(1)
                        Spacer(minLength: 0)
                        if inc.nrcNotified == true {
                            Text("NRC ✓").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.success)
                        } else {
                            Button {
                                nrcTargetId = Int(inc.id.replacingOccurrences(of: "rhi_", with: "")); showNrcSheet = true
                            } label: {
                                Text("LOG NRC").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.blue)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        HStack(spacing: Space.s3) {
            CTAButton(title: filing ? "Filing…" : "Record 171.16 incident", action: { showRecordConfirm = true })
                .frame(maxWidth: .infinity)
                .disabled(filing || topHazmatInspection == nil)
            Button(action: dial) {
                Text("Call \(regimes[regime].2)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132)
                    .frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        Button { showFileNotice = true } label: {
            Text("About the written DOT Form 5800.1")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }.buttonStyle(.plain)
    }

    // MARK: Actions + load

    private var dialDisplay: String {
        switch regime {
        case 0: return "1-800-424-8802"
        case 1: return "1-888-226-8832"
        default: return "800-00-214-00"
        }
    }

    private func dial() {
        if let url = URL(string: "tel:\(regimes[regime].3)") { openURL(url) }
    }

    private func reload() async {
        loading = true
        async let insp: [InspectionRow703] = EusoTripAPI.shared.query(
            "railShipments.getRailInspections", input: LimitInput703(limit: 200))
        async let perms: [HazmatPermitRow703] = EusoTripAPI.shared.query(
            "railShipments.getRailHazmatPermits", input: LimitInput703(limit: 50))
        async let inc: [IncidentReportRow703] = EusoTripAPI.shared.query(
            "railHazmat.getIncidentReports", input: IncidentReportsInput703(limit: 30))
        self.inspections = (try? await insp) ?? []
        self.permits = (try? await perms) ?? []
        self.incidents = (try? await inc) ?? []
        loading = false
    }

    /// The top hazmat-flagged inspection — the real context for a 171.16 filing.
    private var topHazmatInspection: InspectionRow703? {
        inspections.first { Self.isHazmatFlavored($0) && $0.passed == false }
            ?? inspections.first { Self.isHazmatFlavored($0) }
    }

    /// File a real 49 CFR 171.16 incident record (immutable, human-confirmed).
    private func fileIncident() async {
        guard !filing else { return }
        filing = true; defer { filing = false }
        let ctx = topHazmatInspection
        let hay = "\(ctx?.type ?? "") \(ctx?.notes ?? "")".lowercased()
        let un = Self.firstMatch(#"UN\s?(\d{4})"#, in: hay)
        let type: String = hay.contains("fire") ? "fire" : hay.contains("leak") ? "leak" : hay.contains("derail") ? "derailment" : "release"
        do {
            let out: FileIncidentResult703 = try await EusoTripAPI.shared.mutation(
                "railHazmat.fileIncidentReport",
                input: FileIncidentInput703(
                    confirm: true,
                    railcarNumber: ctx?.location,
                    unNumber: un,
                    incidentType: type,
                    location: ctx?.location,
                    description: ctx?.notes ?? "Rail hazmat incident recorded from field per 49 CFR 171.16."
                ))
            if out.success == true {
                fileMessage = "171.16 incident record filed (\(out.incidentId ?? "recorded")). Now log the NRC call reference below."
                await reload()
            } else {
                fileMessage = "The incident record didn't file. Try again."
            }
        } catch {
            fileMessage = "The incident record didn't file. Check your connection and try again."
        }
    }

    /// Log the immutable NRC notification reference for a filed incident.
    private func logNrc() async {
        guard let id = nrcTargetId else { return }
        let num = nrcNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !num.isEmpty else { return }
        do {
            let _: LogNrcResult703 = try await EusoTripAPI.shared.mutation(
                "railHazmat.logNrcNotification", input: LogNrcInput703(incidentId: id, notificationNumber: num))
            showNrcSheet = false; nrcNumber = ""; nrcTargetId = nil
            fileMessage = "NRC notification recorded."
            await reload()
        } catch {
            fileMessage = "Couldn't record the NRC reference. Retry."
        }
    }

    private static func isHazmatFlavored(_ r: InspectionRow703) -> Bool {
        let hay = "\(r.type ?? "") \(r.notes ?? "")".lowercased()
        return hay.contains("hazmat") || hay.contains("release")
            || hay.contains("leak") || hay.contains("spill")
            || firstMatch(#"UN\s?(\d{4})"#, in: hay) != nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard !text.isEmpty,
              let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = rx.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let r = m.numberOfRanges > 1 ? m.range(at: 1) : m.range
        return ns.substring(with: r)
    }

    private static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }

    private static func shortLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d · HH:mm"
        return f.string(from: d)
    }
}

#Preview("703 · Rail Hazmat Incident E-Report · Night") {
    RailHazmatIncidentReportScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("703 · Rail Hazmat Incident E-Report · Light") {
    RailHazmatIncidentReportScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
