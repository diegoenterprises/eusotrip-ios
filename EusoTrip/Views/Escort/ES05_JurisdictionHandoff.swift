//
//  ES05_JurisdictionHandoff.swift
//  EusoTrip — Escort · ES-05 Jurisdiction Handoff (state-line LEO escort).
//
//  Schedules and tracks the pickup/drop of a law-enforcement escort at a
//  jurisdiction boundary. Wired to the real backend spine (fix pack L10-5):
//    REAL  escorts.getActiveAssignments → resolve the live assignment
//    REAL  escorts.getHandoffs          → the scheduled handoffs
//    REAL  escorts.scheduleHandoff      → add a boundary handoff
//    REAL  escorts.markHandoffArrived / completeHandoff / reportHandoffNoShow
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire contracts (mirror server/routers/escorts.ts L10-5)

private struct HOAssignment: Decodable { let id: String; let loadNumber: String?; let pickupLocation: String? }
private struct HOAssignmentsLimit: Encodable { let limit: Int }

private struct LEOHandoff: Decodable, Identifiable {
    let handoffId: Int
    let stateFrom: String?
    let stateTo: String?
    let status: String
    let agency: String?
    let officerRef: String?
    let scheduledAt: String?
    let actualAt: String?
    var id: Int { handoffId }
}
private struct HOGetInput: Encodable { let assignmentId: Int }
private struct HOScheduleInput: Encodable {
    let assignmentId: Int; let stateFrom: String; let stateTo: String
    let scheduledAt: String?; let agency: String?
}
private struct HOScheduleResult: Decodable { let handoffId: Int; let status: String }
private struct HOIdInput: Encodable { let handoffId: Int }
private struct HOStatusResult: Decodable { let handoffId: Int; let status: String }

// MARK: - Screen

struct EscortJurisdictionHandoff: View {
    let assignmentId: String

    @Environment(\.palette) private var palette

    @State private var assignment: HOAssignment? = nil
    @State private var resolvedAssignmentId: Int = 0
    @State private var handoffs: [LEOHandoff] = []
    @State private var loading = true
    @State private var showSchedule = false
    @State private var errorMessage: String? = nil
    @State private var inFlight: Int? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading handoffs…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    if let err = errorMessage { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                    if handoffs.isEmpty {
                        LifecycleCard {
                            Text("No jurisdiction handoffs scheduled. Add one at each state line where a police escort takes over or drops off.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        VStack(spacing: 10) { ForEach(handoffs) { handoffCard($0) } }
                    }
                }
                Color.clear.frame(height: 110)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { scheduleBar }
        .sheet(isPresented: $showSchedule) {
            ScheduleHandoffSheet(onSchedule: { from, to, agency in
                Task { await schedule(from: from, to: to, agency: agency) }
            })
            .environment(\.palette, palette)
        }
        .eusoRefreshTask { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("ESCORT · JURISDICTION HANDOFF").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("State-line handoffs").font(.system(size: 24, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            if let a = assignment {
                Text("Assignment \(a.loadNumber ?? a.id)").font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
        }
    }

    private func handoffCard(_ h: LEOHandoff) -> some View {
        LifecycleCard {
            HStack(spacing: 10) {
                // State-line ribbon marker.
                HStack(spacing: 4) {
                    Text(h.stateFrom ?? "—").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text(h.stateTo ?? "—").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: 0)
                statusPill(h.status)
            }
            VStack(alignment: .leading, spacing: 3) {
                if let ag = h.agency, !ag.isEmpty {
                    Text(ag).font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                if let sched = h.scheduledAt {
                    Text("Scheduled · \(shortTime(sched))").font(EType.mono(.micro)).tracking(0.3).foregroundStyle(palette.textTertiary)
                }
                if let actual = h.actualAt {
                    Text("Arrived · \(shortTime(actual))").font(EType.mono(.micro)).tracking(0.3).foregroundStyle(Brand.success)
                }
            }
            if h.status == "scheduled" || h.status == "arrived" {
                HStack(spacing: 8) {
                    if h.status == "scheduled" {
                        actionButton("Arrived", icon: "checkmark.circle", tint: Brand.success) {
                            Task { await transition(h.handoffId, proc: "escorts.markHandoffArrived") }
                        }
                    }
                    if h.status == "arrived" {
                        actionButton("Complete", icon: "flag.checkered", tint: Brand.success) {
                            Task { await transition(h.handoffId, proc: "escorts.completeHandoff") }
                        }
                    }
                    actionButton("No-show", icon: "exclamationmark.triangle", tint: Brand.danger) {
                        Task { await transition(h.handoffId, proc: "escorts.reportHandoffNoShow") }
                    }
                }
                .disabled(inFlight == h.handoffId)
                .opacity(inFlight == h.handoffId ? 0.5 : 1)
            }
        }
    }

    private func statusPill(_ status: String) -> some View {
        let (label, tint): (String, Color) = {
            switch status {
            case "arrived":   return ("ARRIVED", Brand.warning)
            case "completed": return ("COMPLETE", Brand.success)
            case "no_show":   return ("NO-SHOW", Brand.danger)
            default:          return ("SCHEDULED", palette.textTertiary)
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.7).foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.14)))
    }

    private func actionButton(_ label: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .heavy))
                Text(label).font(.system(size: 11, weight: .heavy))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var scheduleBar: some View {
        Button { showSchedule = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.system(size: 13, weight: .heavy))
                Text("Schedule handoff").font(.system(size: 14, weight: .heavy))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13).foregroundStyle(.white)
            .background(LinearGradient.diagonal).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(resolvedAssignmentId == 0)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: Data

    private func load() async {
        loading = true
        defer { loading = false }
        var aid = Int(assignmentId) ?? 0
        let live: [HOAssignment]? = try? await EusoTripAPI.shared.query(
            "escorts.getActiveAssignments", input: HOAssignmentsLimit(limit: 1))
        if let a = live?.first { assignment = a; if aid == 0 { aid = Int(a.id) ?? 0 } }
        resolvedAssignmentId = aid
        guard aid > 0 else { errorMessage = "No active escort assignment. Accept a job first."; return }
        await refresh()
    }

    private func refresh() async {
        if let rows: [LEOHandoff] = try? await EusoTripAPI.shared.query(
            "escorts.getHandoffs", input: HOGetInput(assignmentId: resolvedAssignmentId)) {
            handoffs = rows
        }
    }

    private func schedule(from: String, to: String, agency: String) async {
        guard resolvedAssignmentId > 0 else { return }
        do {
            let _: HOScheduleResult = try await EusoTripAPI.shared.mutation(
                "escorts.scheduleHandoff",
                input: HOScheduleInput(assignmentId: resolvedAssignmentId, stateFrom: from, stateTo: to,
                                       scheduledAt: nil, agency: agency.isEmpty ? nil : agency))
            await refresh()
        } catch {
            errorMessage = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't schedule the handoff. Try again."
        }
    }

    private func transition(_ handoffId: Int, proc: String) async {
        inFlight = handoffId
        defer { inFlight = nil }
        do {
            let _: HOStatusResult = try await EusoTripAPI.shared.mutation(proc, input: HOIdInput(handoffId: handoffId))
            await refresh()
        } catch {
            errorMessage = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't update the handoff. Try again."
        }
    }

    private func shortTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter(); out.dateFormat = "MMM d · h:mm a"
        return out.string(from: d)
    }
}

// MARK: - Schedule sheet

private struct ScheduleHandoffSheet: View {
    let onSchedule: (_ from: String, _ to: String, _ agency: String) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var from = ""
    @State private var to = ""
    @State private var agency = ""

    private var valid: Bool { from.count == 2 && to.count == 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Schedule handoff").font(.system(size: 20, weight: .heavy)).foregroundStyle(palette.textPrimary)
                HStack(spacing: 12) {
                    field("FROM STATE", text: $from, placeholder: "TX")
                    field("TO STATE", text: $to, placeholder: "OK")
                }
                field("AGENCY (optional)", text: $agency, placeholder: "e.g. OK Highway Patrol")
                Button {
                    onSchedule(from.uppercased(), to.uppercased(), agency)
                    dismiss()
                } label: {
                    Text("Schedule").font(.system(size: 14, weight: .heavy))
                        .frame(maxWidth: .infinity).padding(.vertical, 13).foregroundStyle(.white)
                        .background(valid ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain).disabled(!valid)
            }
            .padding(16)
        }
        .presentationDetents([.medium])
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            TextField(placeholder, text: text)
                .font(EType.body).textInputAutocapitalization(.characters)
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
    }
}

// MARK: - Registered surface wrapper (id 609)

struct EscortJurisdictionHandoffScreen: View {
    let theme: Theme.Palette
    var assignmentId: String = "0"

    var body: some View {
        Shell(theme: theme) {
            EscortJurisdictionHandoff(assignmentId: assignmentId)
        } nav: {
            BottomNav(
                leading: EscortNavRoute.leading(current: .assignments),
                trailing: EscortNavRoute.trailing(current: .assignments),
                orbState: .idle
            )
        }
    }
}

#Preview("ES-05 · Jurisdiction LEOHandoff · Dark") {
    EscortJurisdictionHandoffScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("ES-05 · Jurisdiction LEOHandoff · Light") {
    EscortJurisdictionHandoffScreen(theme: Theme.light).preferredColorScheme(.light)
}
