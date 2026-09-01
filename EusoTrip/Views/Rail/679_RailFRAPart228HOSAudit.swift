//
//  679_RailFRAPart228HOSAudit.swift
//  EusoTrip — Rail Engineer · FRA Part 228 HOS Audit Log.
//
//  Bespoke port of "05 Rail/Dark-SVG/679 Rail FRA Part 228 HOS Audit Log.svg".
//  ARCHETYPE = COURT-OF-RECORD EVENT TIMELINE — a compliance-posture hero
//  (exceptions count + sealed/unsealed chip) over a vertical duty-event rail
//  (node dots on a spine, duty-event type, crew, HOS metrics). Not 675's
//  pre-departure checklist discs, not a static detail card.
//
//  NOTE: type name is Rail-specific (RailFRAPart228HOSAudit*) — the number
//  679 also exists under 06 Vessel (679_VesselEBL) with an unrelated type.
//
//  Role: RAIL_ENGINEER (carrier family). transportMode = rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getRailCrewHOS EXISTS:2125 (queryNoInput) →
//        [{id,role,crewId,onDutyHours,remainingHours,dutyStatus,endorsement}].
//        Each crew member's current duty state is a REAL source row, not a
//        historical event. Exceptions are computed against the 49 CFR Part 228 ceiling
//        from real remaining-hours — never a synthesized violation.
//    HONEST GAP: the immutable per-event hash chain, the window SEAL, and
//    the regulator export have no dedicated rail procedure (getPart228AuditLog
//    / sealAuditWindow — STUB; the blockchainAuditTrail table it would write
//    to is real). The window shows an explicit UNSEALED posture and never
//    paints a fabricated 0x… hash.
//

import SwiftUI

private struct CrewHOS679: Decodable, Identifiable {
    let id: String
    let role: String?
    let crewId: String?
    let onDutyHours: Double?
    let remainingHours: Double?
    let dutyStatus: String?
    let endorsement: String?
    let tracked: Bool?
    let trackingState: HOSTrackingState?
    let source: String?
    let freshness: String?
    let observationState: String?

    enum CodingKeys: String, CodingKey {
        case id, role, crewId, remainingHours, dutyStatus, endorsement, hoursOnDuty
        case tracked, trackingState, source, freshness, observationState
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        if let id = try? c.decode(String.self, forKey: .id), !id.isEmpty {
            self.id = id
        } else if let id = try? c.decode(Int.self, forKey: .id) {
            self.id = String(id)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Crew HOS row has no usable identifier")
        }
        self.role = try c.decodeIfPresent(String.self, forKey: .role)
        self.crewId = try c.decodeIfPresent(String.self, forKey: .crewId)
        if let s = try? c.decodeIfPresent(String.self, forKey: .hoursOnDuty), let h = Double(s) {
            self.onDutyHours = h
        } else {
            self.onDutyHours = try? c.decodeIfPresent(Double.self, forKey: .hoursOnDuty)
        }
        if let hours = try? c.decodeIfPresent(Double.self, forKey: .remainingHours) {
            self.remainingHours = hours
        } else if let hours = try? c.decodeIfPresent(String.self, forKey: .remainingHours) {
            self.remainingHours = Double(hours)
        } else {
            self.remainingHours = nil
        }
        self.dutyStatus = try c.decodeIfPresent(String.self, forKey: .dutyStatus)
        self.endorsement = try c.decodeIfPresent(String.self, forKey: .endorsement)
        self.tracked = try c.decodeIfPresent(Bool.self, forKey: .tracked)
        self.trackingState = try c.decodeIfPresent(HOSTrackingState.self, forKey: .trackingState)
        self.source = try c.decodeIfPresent(String.self, forKey: .source)
        self.freshness = try c.decodeIfPresent(String.self, forKey: .freshness)
        self.observationState = try c.decodeIfPresent(String.self, forKey: .observationState)
    }
}

struct RailFRAPart228HOSAuditScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailFRAPart228HOSAuditBody() } nav: {
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

private struct RailFRAPart228HOSAuditBody: View {
    @Environment(\.palette) private var palette
    @State private var crew: [CrewHOS679] = []
    @State private var loading = true
    @State private var loadError: String?
    private var exceptions: [CrewHOS679] {
        crew.filter { row in
            hasCurrentObservation(row)
                && (row.dutyStatus == "near_limit" || row.remainingHours.map { $0 <= 0 } == true)
        }
    }
    private var unverified: [CrewHOS679] {
        crew.filter { row in
            guard hasCurrentObservation(row) else { return true }
            guard let onDuty = row.onDutyHours, onDuty.isFinite, onDuty >= 0,
                  let remaining = row.remainingHours, remaining.isFinite, remaining >= 0 else {
                return true
            }
            return !["off_duty", "on_duty", "near_limit"].contains(row.dutyStatus ?? "")
        }
    }

    private func isException(_ m: CrewHOS679) -> Bool {
        hasCurrentObservation(m)
            && (m.dutyStatus == "near_limit" || m.remainingHours.map { $0 <= 0 } == true)
    }
    private func eventColor(_ m: CrewHOS679) -> Color {
        guard hasCurrentObservation(m) else { return palette.textTertiary }
        if isException(m) { return Brand.warning }
        switch (m.dutyStatus ?? "") {
        case "on_duty":  return Brand.success
        case "off_duty": return Brand.info
        default:          return Brand.rail
        }
    }
    private func eventType(_ m: CrewHOS679) -> String {
        let evidenceSuffix = hasCurrentObservation(m) ? "" : " · UNVERIFIED"
        switch (m.dutyStatus ?? "") {
        case "on_duty":    return "ON DUTY · \(m.role?.uppercased() ?? "TE") service\(evidenceSuffix)"
        case "off_duty":   return "RELEASED · off duty\(evidenceSuffix)"
        case "near_limit": return "NEAR LIMIT · duty ceiling\(evidenceSuffix)"
        default:            return "DUTY STATUS UNAVAILABLE"
        }
    }

    private func hasCurrentObservation(_ member: CrewHOS679) -> Bool {
        member.tracked == true
            && member.trackingState == .tracked
            && member.observationState == "current"
            && member.source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && HOSObservationClock.freshness(member.freshness).isCurrent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("HOS audit log")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("Current reported crew rows · not a historical audit window")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else if let loadError {
                    EusoEmptyState(
                        systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                        title: "HOS audit source unavailable",
                        subtitle: loadError
                    )
                } else if crew.isEmpty {
                    EusoEmptyState(systemImage: "lock.doc",
                                   title: "No current crew HOS rows",
                                   subtitle: "The Part 228 source returned no crew rows for your company. No compliance posture is inferred.")
                } else {
                    postureHero
                    streamHeader
                    eventStream
                    regimeBand
                    footerActions
                }
            }
            .padding(.horizontal, 20).padding(.top, Space.s5)
        }
        .task { await reload() }
        .eusoRefreshable { await reload() }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            EusoTripEyebrow(verbatim: "RAIL ENGINEER · PART 228 AUDIT LOG")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("UNSEALED SOURCE").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip("\(exceptions.count) verified exception\(exceptions.count == 1 ? "" : "s")",
                 exceptions.isEmpty && unverified.isEmpty ? Brand.success : Brand.warning)
            chip("\(crew.count) source rows", palette.textSecondary)
            chip(unverified.isEmpty ? "unsealed" : "\(unverified.count) unverified", Brand.warning)
        }
    }
    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var postureHero: some View {
        let clean = exceptions.isEmpty && unverified.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FRA 49 CFR PART 228 · SOURCE ROWS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(clean ? Brand.success : Brand.warning)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "lock.open").font(.system(size: 9, weight: .heavy))
                    Text("UNSEALED").font(.system(size: 10.5, weight: .heavy)).tracking(0.4)
                }
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, 10).frame(height: 22)
                .background(Capsule().fill(Brand.warning.opacity(0.16)))
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [Brand.success.opacity(0.12), Brand.blue.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(exceptions.count)").font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text(exceptions.count == 1 ? "verified exception" : "verified exceptions").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
                }
                Text("\(crew.count) duty rows · audit hash unavailable · provider freshness unavailable")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var streamHeader: some View {
        HStack {
            Text("CURRENT CREW SOURCE ROWS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
            Spacer()
            Text("freshness unavailable").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
    }

    private var eventStream: some View {
        VStack(spacing: 0) {
            ForEach(Array(crew.enumerated()), id: \.element.id) { i, m in
                eventNode(m, isLast: i == crew.count - 1)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func eventNode(_ m: CrewHOS679, isLast: Bool) -> some View {
        let color = eventColor(m)
        let ex = isException(m)
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(palette.bgCard).frame(width: 12, height: 12)
                    Circle().stroke(color, lineWidth: 2.5).frame(width: 11, height: 11)
                }
                if !isLast { Rectangle().fill(palette.borderFaint).frame(width: 2).frame(maxHeight: .infinity) }
            }
            .frame(width: 12)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(eventType(m)).font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                    if ex {
                        Text("EXCEPTION").font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Brand.warning)
                            .padding(.horizontal, 6).frame(height: 16)
                            .background(Capsule().fill(Brand.warning.opacity(0.16)))
                    }
                    Spacer()
                    Text(m.crewId ?? "—").font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
                Text(metricSummary(m))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, isLast ? 8 : 18)
        }
        .padding(.top, 8)
    }

    private func metricSummary(_ member: CrewHOS679) -> String {
        guard hasCurrentObservation(member) else {
            return "HOS counters withheld · current sourced observation required"
        }
        let onDuty = member.onDutyHours.map { String(format: "%.1fh on duty", $0) }
            ?? "on-duty hours unavailable"
        let remaining = member.remainingHours.map { String(format: "%.1fh remaining", $0) }
            ?? "remaining hours unavailable"
        return "\(onDuty) · \(remaining)\(member.endorsement.map { " · \($0)" } ?? "")"
    }

    private var regimeBand: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("US · 49 CFR PART 228")
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.blue)
            Text("This source does not evaluate Canadian or Mexican duty regimes.")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.borderFaint))
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Export log", action: {}).frame(maxWidth: .infinity).disabled(true)
            Button {} label: {
                Text("Annotate").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 132).frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }.buttonStyle(.plain).disabled(true)
        }
    }

    private func reload() async {
        loading = true; loadError = nil
        defer { loading = false }
        do {
            crew = try await EusoTripAPI.shared.queryNoInput("railShipments.getRailCrewHOS")
        } catch {
            crew = []
            loadError = "Rail crew HOS rows could not refresh. No audit posture is inferred."
        }
    }
}

#Preview("679 · FRA Part 228 HOS Audit · Night") {
    RailFRAPart228HOSAuditScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("679 · FRA Part 228 HOS Audit · Light") {
    RailFRAPart228HOSAuditScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
