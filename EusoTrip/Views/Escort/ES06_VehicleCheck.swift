//
//  ES06_VehicleCheck.swift
//  EusoTrip — Escort · ES-06 Vehicle Check (pre-trip equipment gate).
//
//  The convoy-release gate: an escort cannot go en_route until a PASSED 12-item
//  pre-trip vehicle check is on file for the assignment (within 24h). Wired to
//  the real backend spine (fix pack L10-4):
//    REAL  escorts.getActiveAssignments → resolve the live assignment
//    REAL  escorts.getVehicleCheck      → template (12 items) + latest inspection
//    REAL  escorts.submitVehicleCheck   → persists the check; passed = all 12 ok
//
//  On submit the backend returns { inspectionId, passed, failedItems } and, when
//  passed, updateJobStatus → en_route is unblocked for the next 24h. A failed
//  check keeps the assignment at accepted/on_site and lists the failed items.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire contracts (mirror server/routers/escorts.ts L10-4)

/// One row in the assignment list (only the fields this screen needs).
private struct VehicleCheckAssignment: Decodable {
    let id: String
    let loadNumber: String?
    let pickupLocation: String?
}
private struct VCAssignmentsLimit: Encodable { let limit: Int }

/// `escorts.getVehicleCheck` → template + latest inspection (or null).
private struct VCTemplateItem: Decodable, Identifiable {
    let key: String
    let label: String
    var id: String { key }
}
private struct VCLatest: Decodable {
    let inspectionId: Int
    let passed: Bool
    let failedItems: [String]
    let signedAt: String?
}
private struct VCGetResult: Decodable {
    let assignmentId: Int
    let latest: VCLatest?
    let template: [VCTemplateItem]
}
private struct VCGetInput: Encodable { let assignmentId: Int }

/// `escorts.submitVehicleCheck`.
private struct VCChecklistItem: Encodable { let key: String; let ok: Bool; let note: String? }
private struct VCSubmitInput: Encodable {
    let assignmentId: Int
    let vehicleDesc: String?
    let odometer: Int?
    let checklist: [VCChecklistItem]
}
private struct VCSubmitResult: Decodable { let inspectionId: Int; let passed: Bool; let failedItems: [String] }

/// The local editing model for one checklist row.
private struct ChecklistRow: Identifiable {
    let key: String
    let label: String
    var ok: Bool = false
    var note: String = ""
    var id: String { key }
}

// MARK: - Screen

struct EscortVehicleCheck: View {
    let assignmentId: String

    @Environment(\.palette) private var palette

    @State private var assignment: VehicleCheckAssignment? = nil
    @State private var resolvedAssignmentId: Int = 0
    @State private var rows: [ChecklistRow] = []
    @State private var vehicleDesc: String = ""
    @State private var odometerText: String = ""

    @State private var loading: Bool = true
    @State private var submitting: Bool = false
    @State private var lastPassed: Bool? = nil
    @State private var lastFailed: [String] = []
    @State private var errorMessage: String? = nil
    @State private var priorSignedAt: String? = nil

    private var allOk: Bool { !rows.isEmpty && rows.allSatisfy { $0.ok } }
    private var okCount: Int { rows.filter { $0.ok }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading checklist…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    resultBanner
                    vehicleCard
                    checklistCard
                }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { submitBar }
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESCORT · VEHICLE CHECK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Pre-trip equipment gate")
                .font(.system(size: 24, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            if let a = assignment {
                Text("Assignment \(a.loadNumber ?? a.id)\(a.pickupLocation.map { " · \($0)" } ?? "")")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            if let prior = priorSignedAt {
                Text("Last check on file · \(prior)")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    @ViewBuilder private var resultBanner: some View {
        if let passed = lastPassed {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: passed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(passed ? Brand.success : Brand.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text(passed ? "Passed · en route unlocked for 24h" : "Not passed — \(lastFailed.count) item\(lastFailed.count == 1 ? "" : "s") outstanding")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    if !passed, !lastFailed.isEmpty {
                        Text(lastFailed.map { label(for: $0) }.joined(separator: " · "))
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((passed ? Brand.success : Brand.danger).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder((passed ? Brand.success : Brand.danger).opacity(0.4)))
        } else if let err = errorMessage {
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
    }

    // MARK: Vehicle card

    private var vehicleCard: some View {
        LifecycleCard {
            sectionEyebrow("VEHICLE", icon: "car")
            VStack(spacing: 8) {
                labeledField(title: "Description", text: $vehicleDesc, placeholder: "e.g. F-250 · white · TX 8ABC123")
                labeledField(title: "Odometer", text: $odometerText, placeholder: "miles", keyboard: .numberPad)
            }
        }
    }

    // MARK: Checklist

    private var checklistCard: some View {
        LifecycleCard {
            HStack(spacing: 6) {
                sectionEyebrow("12-POINT CHECK", icon: "checklist")
                Spacer(minLength: 0)
                Text("\(okCount)/12")
                    .font(.system(size: 11, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(allOk ? Brand.success : palette.textTertiary)
            }
            VStack(spacing: 6) {
                ForEach($rows) { $row in
                    checklistRow($row)
                }
            }
        }
    }

    private func checklistRow(_ row: Binding<ChecklistRow>) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { row.wrappedValue.ok.toggle() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(row.wrappedValue.ok ? AnyShapeStyle(Brand.success) : AnyShapeStyle(palette.bgCardSoft))
                            .frame(width: 34, height: 34)
                        Image(systemName: row.wrappedValue.ok ? "checkmark" : "xmark")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(row.wrappedValue.ok ? .white : Brand.danger)
                    }
                }
                .buttonStyle(.plain)
                Text(row.wrappedValue.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            // Note field expands only when the item is marked not-ok.
            if !row.wrappedValue.ok {
                TextField("Note (what's missing / to fix)", text: row.note, axis: .vertical)
                    .font(EType.caption)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Brand.danger.opacity(0.35)))
                    .padding(.leading, 46)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: Submit bar

    private var submitBar: some View {
        VStack(spacing: 0) {
            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 8) {
                    if submitting { ProgressView().scaleEffect(0.8).tint(.white) }
                    Image(systemName: allOk ? "signature" : "checklist")
                        .font(.system(size: 13, weight: .heavy))
                    Text(allOk ? "Sign & submit — all clear" : "Submit check (\(okCount)/12)")
                        .font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(allOk ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(submitting || rows.isEmpty || resolvedAssignmentId == 0)
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: Primitives

    private func sectionEyebrow(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

    private func labeledField(title: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 10) {
            Text(title).font(EType.caption).foregroundStyle(palette.textTertiary).frame(width: 92, alignment: .leading)
            TextField(placeholder, text: text)
                .font(EType.body).keyboardType(keyboard)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCardSoft)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
    }

    private func label(for key: String) -> String {
        rows.first(where: { $0.key == key })?.label ?? key
    }

    // MARK: Data

    private func load() async {
        loading = true
        defer { loading = false }
        // Resolve the assignment: use the injected id, else the live active one.
        var aid = Int(assignmentId) ?? 0
        let live: [VehicleCheckAssignment]? = try? await EusoTripAPI.shared.query(
            "escorts.getActiveAssignments", input: VCAssignmentsLimit(limit: 1))
        if let a = live?.first {
            assignment = a
            if aid == 0 { aid = Int(a.id) ?? 0 }
        }
        resolvedAssignmentId = aid
        guard aid > 0 else {
            errorMessage = "No active escort assignment to check. Accept a job first."
            return
        }
        // Load the 12-item template (and any prior inspection).
        if let res: VCGetResult = try? await EusoTripAPI.shared.query(
            "escorts.getVehicleCheck", input: VCGetInput(assignmentId: aid)) {
            rows = res.template.map { ChecklistRow(key: $0.key, label: $0.label) }
            if let latest = res.latest {
                priorSignedAt = latest.signedAt
                lastPassed = latest.passed
                lastFailed = latest.failedItems
            }
        }
    }

    private func submit() async {
        guard resolvedAssignmentId > 0, rows.count == 12 else { return }
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        let checklist = rows.map { VCChecklistItem(key: $0.key, ok: $0.ok, note: $0.ok ? nil : ($0.note.isEmpty ? nil : $0.note)) }
        let odometer = Int(odometerText.filter(\.isNumber))
        do {
            let out: VCSubmitResult = try await EusoTripAPI.shared.mutation(
                "escorts.submitVehicleCheck",
                input: VCSubmitInput(
                    assignmentId: resolvedAssignmentId,
                    vehicleDesc: vehicleDesc.isEmpty ? nil : vehicleDesc,
                    odometer: odometer,
                    checklist: checklist
                )
            )
            lastPassed = out.passed
            lastFailed = out.failedItems
        } catch {
            // Surface the server's own message (e.g. the PRECONDITION gate copy)
            // verbatim; fall back to an honest generic line.
            errorMessage = (error as? EusoTripAPIError)?.errorDescription
                ?? "Couldn't submit the vehicle check. Try again."
        }
    }
}

// MARK: - Registered surface wrapper (id 608)

struct EscortVehicleCheckScreen: View {
    let theme: Theme.Palette
    var assignmentId: String = "0"

    var body: some View {
        Shell(theme: theme) {
            EscortVehicleCheck(assignmentId: assignmentId)
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home",        systemImage: "house",                  isCurrent: false),
                    NavSlot(label: "Assignments", systemImage: "shield.lefthalf.filled", isCurrent: true),
                ],
                trailing: [
                    NavSlot(label: "Corridor", systemImage: "map",    isCurrent: false),
                    NavSlot(label: "Me",       systemImage: "person", isCurrent: false),
                ],
                orbState: .idle
            )
        }
    }
}

#Preview("ES-06 · Vehicle Check · Dark") {
    EscortVehicleCheckScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("ES-06 · Vehicle Check · Light") {
    EscortVehicleCheckScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
