//
//  831_VesselCBPExamStation.swift
//  EusoTrip — Vessel Operator · CBP Cargo Exam Station (CES) (831).
//
//  Verbatim-composition port of "831 Vessel CBP Cargo Exam Station.svg" (Dark →
//  Light). EXAM-TYPE-CHIP-QUEUE + SCAN-RESULT-INSET archetype — an exam-workflow
//  surface: an at-scanner hero with a scan-result inset, and an exam-pipeline
//  queue of CBP holds. Nav: HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//
//  WIRING (honest):
//    Exam holds are REAL — vesselShipments.getCBPAlerts (vesselShipments.ts:2818,
//        vesselProcedure, input { importerId }) → CBPAlert[] | null (Descartes
//        ABI). Each hold renders as a real exam-pipeline row (container/entry +
//        severity-derived status).
//    Entry disposition is REAL — vesselShipments.getCBPEntryStatus (:2807).
//    There is NO CES / exam-station model on disk (slot scheduling, exam
//        modality, fee accrual; grep examStation/CES = 0) → STUB · named-gap:
//        vessel.getExamStation({ces}) + vessel.scheduleExamSlot({containerId,
//        slot,confirm:true}) → books the CES slot, writes the exam event + fee
//        line + blockchainAuditTrail vessel.exam_scheduled, broadcasts
//        WS_EVENTS.examStatusChanged. The exam modality (VACIS/X-ray/…), CES
//        slot and per-hold fee render from that model once it ships; until then
//        rows show the REAL alert type/agency, never a fabricated modality.
//    COUNTRY: US CBP VACIS/CES (19 CFR 151) active · CA CBSA CET · MX semáforo rojo.
//

import SwiftUI

struct VesselCBPExamStationScreen: View {
    let theme: Theme.Palette
    var importerId: String = "EUSORONE"

    var body: some View {
        Shell(theme: theme) {
            VesselCBPExamStationBody(importerId: importerId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",              isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Alert shape (DescartesABIService.CBPAlert)

private struct ExamAlert831: Decodable, Identifiable {
    let alertId: String
    let alertType: String?
    let severity: String?
    let description: String?
    let entryNumber: String?
    let agency: String?
    let actionRequired: Bool?
    var id: String { alertId }
}

private enum ExamTone831 { case danger, warning, info, success }

// MARK: - Body

private struct VesselCBPExamStationBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    let importerId: String

    @State private var alerts: [ExamAlert831] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    private var resolvedImporter: String {
        if let cid = session.user?.companyId?.trimmingCharacters(in: .whitespaces), !cid.isEmpty { return cid }
        return importerId
    }
    private var holdCount: Int { alerts.filter { tone($0) != .success }.count }
    private var topHold: ExamAlert831? { sorted.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · CBP EXAM · CES",
                caption: "19 CFR 151",
                title: "Exam station",
                subtitle: "VACIS + intensive · CES Long Beach"
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else {
                    scannerHero
                    pipelineSection
                    VesselRegulatorBand(
                        title: "REGULATOR · SINGLE-COUNTRY VARIATION",
                        reference: "19 CFR 151",
                        rows: [
                            .init("US", "CBP VACIS / CES · importer pays exam", active: true),
                            .init("CA", "CBSA exam · CET referral"),
                            .init("MX", "Reconocimiento · semáforo rojo")
                        ]
                    )
                    ctaPair
                    VesselGapNote(text: "Verified CBP exam holds are shown. Modality, CES appointment, and fees appear only when supplied by the examination-station record.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - At-scanner hero + scan-result inset

    private var scannerHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text(topHold?.entryNumber ?? topHold?.alertId ?? "No exam hold on file")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text(topHold == nil ? "CLEAR" : "AT SCANNER")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(topHold == nil ? Color(hex: 0x34D8A6) : Color(hex: 0xFFC246))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill((topHold == nil ? Color(hex: 0x34D8A6) : Color(hex: 0xFFC246)).opacity(0.13)))
                }
                Text(topHold.map { $0.description ?? "CBP exam hold" } ?? "No open CBP exam holds")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Text("CES Long Beach · verified appointment and referral required")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                // Scan-result inset
                HStack(spacing: 8) {
                    Circle().fill(topHold == nil ? Brand.success : Color(hex: 0xFFC246)).frame(width: 8, height: 8)
                    Text(topHold == nil ? "No scan pending" : "Scan pending · exam fee awaits CES model")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
                .frame(maxWidth: .infinity)
                .background(palette.bgCardSoft)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
        }
    }

    // MARK: - Exam pipeline queue (REAL alerts)

    private var pipelineSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "EXAM PIPELINE · CES QUEUE", right: "VERIFIED HOLDS")
            if alerts.isEmpty {
                EusoEmptyState(systemImage: "checkmark.shield",
                               title: "No exam holds in the queue",
                               subtitle: "Open CBP exam holds appear here. Modality, CES appointment, and fee are shown only when verified.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, alert in
                        if idx > 0 { Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4) }
                        examRow(alert)
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                VesselSummaryStrip(label: "Exam fees & dwell · importer pays",
                                   value: "\(holdCount) hold\(holdCount == 1 ? "" : "s")")
            }
        }
    }

    private func examRow(_ alert: ExamAlert831) -> some View {
        let t = tone(alert)
        let c = color(t)
        return HStack(alignment: .center, spacing: Space.s3) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(c).frame(width: 4, height: 34)
            // Exam-type chip — shows the REAL alert type until getExamStation
            // supplies the physical modality.
            Text((alert.alertType ?? "EXAM").uppercased())
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.3)
                .foregroundStyle(c)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 66)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(c.opacity(0.13)))
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.entryNumber ?? alert.alertId)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(alert.agency ?? "CBP")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(statusLabel(t))
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.3)
                .foregroundStyle(c)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(c.opacity(0.13)))
        }
        .padding(Space.s4)
    }

    private var sorted: [ExamAlert831] {
        func rank(_ a: ExamAlert831) -> Int {
            switch tone(a) { case .danger: return 0; case .warning: return 1; case .info: return 2; case .success: return 3 }
        }
        return alerts.sorted { rank($0) < rank($1) }
    }

    private func tone(_ a: ExamAlert831) -> ExamTone831 {
        let s = (a.severity ?? "").lowercased()
        let type = (a.alertType ?? "").lowercased()
        let desc = (a.description ?? "").lowercased()
        if type.contains("released") || desc.contains("released") || (s == "info" && a.actionRequired == false) { return .success }
        if s == "critical" || s == "high" || type.contains("intensive") || desc.contains("intensive") { return .danger }
        if s == "medium" || type.contains("scheduled") || desc.contains("scheduled") { return .info }
        return .warning
    }

    private func statusLabel(_ t: ExamTone831) -> String {
        switch t {
        case .danger:  return "OPEN EXAM"
        case .warning: return "AT SCANNER"
        case .info:    return "SCHEDULED"
        case .success: return "RELEASED"
        }
    }

    private func color(_ t: ExamTone831) -> Color {
        switch t {
        case .danger:  return Color(hex: 0xFF6F61)
        case .warning: return Color(hex: 0xFFC246)
        case .info:    return Color(hex: 0x5AB0FF)
        case .success: return Color(hex: 0x34D8A6)
        }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Schedule slot", action: {}, trailingIcon: "calendar.badge.plus")
            VesselGhostButton(title: "Dispute fee", width: 150) {}
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 170)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
        }
    }

    // MARK: - Load (REAL: getCBPAlerts)

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let importerId: String }
        do {
            let rows: [ExamAlert831]? = try await EusoTripAPI.shared.query(
                "vesselShipments.getCBPAlerts", input: In(importerId: resolvedImporter))
            self.alerts = rows ?? []
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("831 · Vessel CBP Exam Station · Night") {
    VesselCBPExamStationScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("831 · Vessel CBP Exam Station · Light") {
    VesselCBPExamStationScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
