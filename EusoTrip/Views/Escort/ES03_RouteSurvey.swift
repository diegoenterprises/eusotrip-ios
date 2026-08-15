//
//  ES03_RouteSurvey.swift
//  EusoTrip — Escort · ES-03 Route Survey (pre-move hazard log).
//
//  The pre-move route survey an escort captures before a permitted OS/OW move —
//  the compliance evidence trail. Wired to the real backend spine (fix pack
//  L10-2):
//    REAL  escorts.getActiveAssignments → resolve the live assignment
//    REAL  escorts.startRouteSurvey     → open/reuse the draft survey
//    REAL  escorts.getRouteSurvey       → survey + logged hazards
//    REAL  escorts.logSurveyHazard      → append a hazard (9 kinds)
//    REAL  escorts.completeRouteSurvey  → draft → submitted
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire contracts (mirror server/routers/escorts.ts L10-2)

private struct RSAssignment: Decodable { let id: String; let loadNumber: String?; let pickupLocation: String? }
private struct RSAssignmentsLimit: Encodable { let limit: Int }

private struct RSStartInput: Encodable { let assignmentId: Int; let vehicleHeightFt: Double?; let vehicleWidthFt: Double? }
private struct RSStartResult: Decodable { let surveyId: Int; let status: String }

private struct RSHazard: Decodable, Identifiable {
    let hazardId: Int
    let seq: Int
    let kind: String
    let measuredClearanceFt: String?
    let note: String?
    let loggedAt: String?
    var id: Int { hazardId }
}
private struct RSSurvey: Decodable {
    let surveyId: Int
    let status: String
    let vehicleHeightFt: String?
    let summary: String?
    let completedAt: String?
}
private struct RSGetResult: Decodable { let survey: RSSurvey?; let hazards: [RSHazard] }
private struct RSGetInput: Encodable { let assignmentId: Int }

private struct RSLogInput: Encodable {
    let surveyId: Int
    let kind: String
    let measuredClearanceFt: Double?
    let note: String?
}
private struct RSLogResult: Decodable { let hazardId: Int; let seq: Int }
private struct RSCompleteInput: Encodable { let surveyId: Int; let summary: String? }
private struct RSCompleteResult: Decodable { let status: String; let hazardCount: Int }

/// The 9 canonical hazard kinds (mirror the server enum) + display label + icon.
private struct HazardKind: Identifiable {
    let key: String; let label: String; let icon: String
    var id: String { key }
}
private let HAZARD_KINDS: [HazardKind] = [
    .init(key: "LOW_CLEARANCE", label: "Low clearance", icon: "arrow.up.and.down.circle"),
    .init(key: "NARROW_LANE", label: "Narrow lane", icon: "arrow.left.and.right.circle"),
    .init(key: "CONSTRUCTION", label: "Construction", icon: "cone"),
    .init(key: "RAIL_CROSSING", label: "Rail crossing", icon: "tram"),
    .init(key: "TIGHT_TURN", label: "Tight turn", icon: "arrow.uturn.right"),
    .init(key: "UTILITY_LINE", label: "Utility line", icon: "bolt"),
    .init(key: "WEIGHT_RESTRICTED_BRIDGE", label: "Weight-restricted bridge", icon: "scalemass"),
    .init(key: "CURFEW_ZONE", label: "Curfew zone", icon: "clock.badge.exclamationmark"),
    .init(key: "OTHER", label: "Other", icon: "exclamationmark.triangle"),
]
private func hazardMeta(_ key: String) -> HazardKind {
    HAZARD_KINDS.first(where: { $0.key == key }) ?? HAZARD_KINDS.last!
}

// MARK: - Screen

struct EscortRouteSurvey: View {
    let assignmentId: String

    @Environment(\.palette) private var palette

    @State private var assignment: RSAssignment? = nil
    @State private var resolvedAssignmentId: Int = 0
    @State private var surveyId: Int = 0
    @State private var status: String = "draft"
    @State private var hazards: [RSHazard] = []
    @State private var poleHeightText: String = ""

    @State private var loading = true
    @State private var showAddHazard = false
    @State private var submitting = false
    @State private var errorMessage: String? = nil

    private var lowestClearance: Double? {
        hazards.compactMap { $0.measuredClearanceFt.flatMap(Double.init) }.min()
    }
    private var poleHeight: Double? { Double(poleHeightText.filter { $0.isNumber || $0 == "." }) }
    private var marginColor: Color {
        guard let low = lowestClearance, let pole = poleHeight else { return palette.textTertiary }
        let margin = low - pole
        if margin < 0 { return Brand.danger }
        if margin < 0.5 { return Brand.warning }
        return Brand.success
    }
    private var isSubmitted: Bool { status == "submitted" || status == "approved" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading survey…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    if let err = errorMessage {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    measurementCard
                    hazardLogCard
                }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { footerBar }
        .sheet(isPresented: $showAddHazard) {
            AddHazardSheet(onLog: { kind, clearance, note in
                Task { await logHazard(kind: kind, clearance: clearance, note: note) }
            })
            .environment(\.palette, palette)
        }
        .eusoRefreshTask { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "map").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("ESCORT · ROUTE SURVEY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Pre-move hazard log").font(.system(size: 24, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            if let a = assignment {
                Text("Assignment \(a.loadNumber ?? a.id)\(a.pickupLocation.map { " · \($0)" } ?? "")")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            if isSubmitted {
                Text("Submitted — this survey is on file for permit compliance")
                    .font(EType.mono(.micro)).tracking(0.3).foregroundStyle(Brand.success)
            }
        }
    }

    // Sticky measurement summary: pole height vs lowest logged clearance + margin.
    private var measurementCard: some View {
        LifecycleCard {
            HStack(spacing: 6) {
                Image(systemName: "ruler").font(.system(size: 11, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CLEARANCE MARGIN").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("POLE HEIGHT").font(.system(size: 8.5, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                    TextField("ft", text: $poleHeightText)
                        .font(EType.mono(.body)).keyboardType(.decimalPad)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(palette.bgCardSoft).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        .frame(width: 80)
                }
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOWEST LOGGED").font(.system(size: 8.5, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                    Text(lowestClearance.map { String(format: "%.1f ft", $0) } ?? "—")
                        .font(EType.mono(.body)).foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: 0)
                Circle().fill(marginColor).frame(width: 12, height: 12)
            }
        }
    }

    private var hazardLogCard: some View {
        LifecycleCard {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.clipboard").font(.system(size: 11, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("HAZARD LOG").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Text("\(hazards.count)").font(.system(size: 11, weight: .heavy)).monospacedDigit().foregroundStyle(palette.textTertiary)
            }
            if hazards.isEmpty {
                Text("No hazards logged yet. Tap + Hazard as you drive the route, or complete a clear route below.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(hazards) { h in hazardRow(h) }
                }
            }
        }
    }

    private func hazardRow(_ h: RSHazard) -> some View {
        let meta = hazardMeta(h.kind)
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 34, height: 34)
                Image(systemName: meta.icon).font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                if let note = h.note, !note.isEmpty {
                    Text(note).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if let c = h.measuredClearanceFt.flatMap(Double.init) {
                Text(String(format: "%.1f ft", c)).font(EType.mono(.caption)).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.vertical, 3)
    }

    private var footerBar: some View {
        VStack(spacing: 8) {
            if !isSubmitted {
                Button { showAddHazard = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 13, weight: .heavy))
                        Text("Add hazard").font(.system(size: 13, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .foregroundStyle(LinearGradient.diagonal)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.5)))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(surveyId == 0)
            }
            Button { Task { await complete() } } label: {
                HStack(spacing: 8) {
                    if submitting { ProgressView().scaleEffect(0.8).tint(.white) }
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 13, weight: .heavy))
                    Text(isSubmitted ? "Survey submitted" : "Complete survey").font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(isSubmitted ? AnyShapeStyle(palette.textTertiary) : AnyShapeStyle(LinearGradient.diagonal))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(submitting || isSubmitted || surveyId == 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: Data

    private func load() async {
        loading = true
        defer { loading = false }
        var aid = Int(assignmentId) ?? 0
        let live: [RSAssignment]? = try? await EusoTripAPI.shared.query(
            "escorts.getActiveAssignments", input: RSAssignmentsLimit(limit: 1))
        if let a = live?.first { assignment = a; if aid == 0 { aid = Int(a.id) ?? 0 } }
        resolvedAssignmentId = aid
        guard aid > 0 else { errorMessage = "No active escort assignment to survey. Accept a job first."; return }
        // Load any existing survey; if none, open a draft.
        if let res: RSGetResult = try? await EusoTripAPI.shared.query(
            "escorts.getRouteSurvey", input: RSGetInput(assignmentId: aid)) {
            hazards = res.hazards
            if let s = res.survey {
                surveyId = s.surveyId; status = s.status
                if let h = s.vehicleHeightFt { poleHeightText = h }
            }
        }
        if surveyId == 0 {
            if let start: RSStartResult = try? await EusoTripAPI.shared.mutation(
                "escorts.startRouteSurvey", input: RSStartInput(assignmentId: aid, vehicleHeightFt: poleHeight, vehicleWidthFt: nil)) {
                surveyId = start.surveyId; status = start.status
            }
        }
    }

    private func logHazard(kind: String, clearance: Double?, note: String?) async {
        guard surveyId > 0 else { return }
        do {
            let _: RSLogResult = try await EusoTripAPI.shared.mutation(
                "escorts.logSurveyHazard",
                input: RSLogInput(surveyId: surveyId, kind: kind, measuredClearanceFt: clearance, note: note))
            // Refresh from the server so seq + ordering are authoritative.
            if let res: RSGetResult = try? await EusoTripAPI.shared.query(
                "escorts.getRouteSurvey", input: RSGetInput(assignmentId: resolvedAssignmentId)) {
                hazards = res.hazards
            }
        } catch {
            errorMessage = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't log the hazard. Try again."
        }
    }

    private func complete() async {
        guard surveyId > 0, !isSubmitted else { return }
        submitting = true; errorMessage = nil
        defer { submitting = false }
        do {
            let out: RSCompleteResult = try await EusoTripAPI.shared.mutation(
                "escorts.completeRouteSurvey", input: RSCompleteInput(surveyId: surveyId, summary: nil))
            status = out.status
        } catch {
            errorMessage = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't complete the survey. Try again."
        }
    }
}

// MARK: - Add-hazard sheet

private struct AddHazardSheet: View {
    let onLog: (_ kind: String, _ clearance: Double?, _ note: String) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var kind: String = HAZARD_KINDS.first!.key
    @State private var clearanceText: String = ""
    @State private var note: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Log a hazard").font(.system(size: 20, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("KIND").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(HAZARD_KINDS) { k in
                        Button { kind = k.key } label: {
                            HStack(spacing: 8) {
                                Image(systemName: k.icon).font(.system(size: 13, weight: .heavy))
                                Text(k.label).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 10)
                            .foregroundStyle(kind == k.key ? .white : palette.textPrimary)
                            .background(kind == k.key ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("MEASURED CLEARANCE (ft, optional)").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                TextField("e.g. 15.5", text: $clearanceText)
                    .font(EType.body).keyboardType(.decimalPad)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                Text("NOTE (optional)").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                TextField("What to watch for", text: $note, axis: .vertical)
                    .font(EType.body)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                Button {
                    let clearance = Double(clearanceText.filter { $0.isNumber || $0 == "." })
                    onLog(kind, clearance, note)
                    dismiss()
                } label: {
                    Text("Log hazard").font(.system(size: 14, weight: .heavy))
                        .frame(maxWidth: .infinity).padding(.vertical, 13).foregroundStyle(.white)
                        .background(LinearGradient.diagonal).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Registered surface wrapper (id 606)

struct EscortRouteSurveyScreen: View {
    let theme: Theme.Palette
    var assignmentId: String = "0"

    var body: some View {
        Shell(theme: theme) {
            EscortRouteSurvey(assignmentId: assignmentId)
        } nav: {
            BottomNav(
                leading: EscortNavRoute.leading(current: .assignments),
                trailing: EscortNavRoute.trailing(current: .assignments),
                orbState: .idle
            )
        }
    }
}

#Preview("ES-03 · Route Survey · Dark") {
    EscortRouteSurveyScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("ES-03 · Route Survey · Light") {
    EscortRouteSurveyScreen(theme: Theme.light).preferredColorScheme(.light)
}
