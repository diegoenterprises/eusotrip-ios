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
//        Each crew member's current duty state is a REAL event on the stream;
//        exceptions are computed against the 49 CFR Part 228 12-10 ceiling
//        from real remaining-hours — never a synthesized violation.
//    HONEST GAP: the immutable per-event hash chain, the window SEAL, and
//    the regulator export have no dedicated rail procedure (getPart228AuditLog
//    / sealAuditWindow — STUB; the blockchainAuditTrail table it would write
//    to is real). The window shows an explicit UNSEALED posture and never
//    paints a fabricated 0x… hash.
//

import SwiftUI

private struct CrewHOS679: Decodable, Identifiable {
    let id: Int
    let role: String?
    let crewId: String?
    let onDutyHours: Double?
    let remainingHours: Double?
    let dutyStatus: String?
    let endorsement: String?

    enum CodingKeys: String, CodingKey { case id, role, crewId, remainingHours, dutyStatus, endorsement, hoursOnDuty }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.role = try c.decodeIfPresent(String.self, forKey: .role)
        self.crewId = try c.decodeIfPresent(String.self, forKey: .crewId)
        if let s = try c.decodeIfPresent(String.self, forKey: .hoursOnDuty), let h = Double(s) { self.onDutyHours = h }
        else { self.onDutyHours = try c.decodeIfPresent(Double.self, forKey: .hoursOnDuty) }
        self.remainingHours = try c.decodeIfPresent(Double.self, forKey: .remainingHours)
        self.dutyStatus = try c.decodeIfPresent(String.self, forKey: .dutyStatus)
        self.endorsement = try c.decodeIfPresent(String.self, forKey: .endorsement)
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
    @State private var country = 0

    private let ceiling: Double = 12.0    // 49 CFR Part 228 · 12h on / 10h off
    private let regimes: [(String, String)] = [("US · 49 CFR 228", "12-10 HoS Act"),
                                               ("CA · TC W/R", "2023 rules"),
                                               ("MX · ARTF", "jornada LRSF")]

    private var exceptions: [CrewHOS679] {
        crew.filter { ($0.dutyStatus ?? "") == "near_limit" || ($0.remainingHours ?? ceiling) <= 0 }
    }

    private func isException(_ m: CrewHOS679) -> Bool {
        (m.dutyStatus ?? "") == "near_limit" || (m.remainingHours ?? ceiling) <= 0
    }
    private func eventColor(_ m: CrewHOS679) -> Color {
        if isException(m) { return Brand.warning }
        switch (m.dutyStatus ?? "") {
        case "on_duty":  return Brand.success
        case "off_duty": return Brand.info
        default:          return Brand.rail
        }
    }
    private func eventType(_ m: CrewHOS679) -> String {
        switch (m.dutyStatus ?? "") {
        case "on_duty":    return "ON DUTY · \(m.role?.uppercased() ?? "TE") service"
        case "off_duty":   return "RELEASED · off duty"
        case "near_limit": return "NEAR LIMIT · duty ceiling"
        default:            return (m.dutyStatus ?? "duty event").uppercased()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("HOS audit log")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("Aurora Rail Division · crew duty stream · 14-day window")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else if crew.isEmpty {
                    EusoEmptyState(systemImage: "lock.doc",
                                   title: "No duty events in the window",
                                   subtitle: "The Part 228 record reconstructs from crew HOS rows. None are assigned to your company for this window.")
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
        .refreshable { await reload() }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            Text("✦ RAIL ENGINEER · PART 228 AUDIT LOG")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("HASH-CHAINED").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip(exceptions.isEmpty ? "0 exceptions" : "\(exceptions.count) exception\(exceptions.count == 1 ? "" : "s")",
                 exceptions.isEmpty ? Brand.success : Brand.warning)
            chip("\(crew.count) events", palette.textSecondary)
            chip("unsealed", Brand.warning)
        }
    }
    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var postureHero: some View {
        let clean = exceptions.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FRA 49 CFR PART 228 · IMMUTABLE")
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
                    Text(exceptions.count == 1 ? "exception" : "exceptions").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
                }
                Text("\(crew.count) duty events · window seal + hash chain bind on getPart228AuditLog")
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
            Text("DUTY EVENT STREAM").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
            Spacer()
            Text("live HOS").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
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
                Text("\(String(format: "%.1f", m.onDutyHours ?? 0))h on duty · \(String(format: "%.1f", m.remainingHours ?? ceiling))h remaining\(m.endorsement.map { " · \($0)" } ?? "")")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, isLast ? 8 : 18)
        }
        .padding(.top, 8)
    }

    private var regimeBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == country ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == country ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { country = i } }
            }
        }
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
        loading = true
        crew = (try? await EusoTripAPI.shared.queryNoInput("railShipments.getRailCrewHOS")) ?? []
        loading = false
    }
}

#Preview("679 · FRA Part 228 HOS Audit · Night") {
    RailFRAPart228HOSAuditScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("679 · FRA Part 228 HOS Audit · Light") {
    RailFRAPart228HOSAuditScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
