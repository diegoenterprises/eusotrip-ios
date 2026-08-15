//
//  ES20_OnboardingRegistration.swift
//  EusoTrip — Escort · Onboarding & Registration (ES-20).
//
//  Built from the ES-20 design-authority SVG pair
//  ("07 Escort/{Light,Dark}-SVG/ES-20 Onboarding Registration.svg").
//
//  ARCHETYPE — TIMELINE wizard · HORIZONTAL GATE TRACK. The 0→solo pipeline is
//  one left-to-right rail that is PHYSICALLY INTERRUPTED by its own blockers: a
//  cleared gate is a raised arm with the rail running clean beneath it; a
//  blocking gate is a barrier bar that CROSSES the rail and kills it, so
//  everything past the first closed barrier is dashed dead track; a
//  non-blocking gate is a notch hanging ABOVE the rail on a stem that never
//  touches it; and the terminus is an UNFILLED ring, because SOLO is not
//  earned. A gradient wedge marked YOU sits pressed against the closed
//  barrier. Beneath the rail is the wizard's real subject: a COST panel that
//  prices the next irreversible action BEFORE it is taken.
//
//  Deliberately NOT ES-08 Cert Reciprocity, the nearest sibling: ES-08 is a
//  51-tile choropleth colouring LAW by geography — a MAP, load-independent and
//  steady-state, whose gates are STATES. ES-20 has zero map and zero
//  jurisdiction tiles; it is a one-dimensional, time-ordered admission ladder
//  whose gates are STAGES. Also NOT ES-05 / ES-16 (both VERTICAL spines with a
//  blown-out hero node), NOT ES-12's rising cert staircase, NOT ES-06's
//  12-tile equipment BentoGrid.
//
//  ─── WIRING (every anchor opened at the line first-hand this fire; escorts.ts
//      cites pinned to md5 064a1b8459b8 · 4745 lines · 2026-08-10T22:41:39-05:00)
//
//    EXISTS onboarding.getStatus            onboarding.ts:20    gate-1 completion, steps, %
//    EXISTS onboarding.getSteps             onboarding.ts:71    current step id for COMPLETE
//    EXISTS onboarding.getProgress          onboarding.ts:387   server-side progress rollup
//    EXISTS onboarding.getRequiredDocuments onboarding.ts:424   per-doc uploaded/status/expiry
//    EXISTS onboarding.uploadDocument       onboarding.ts:509   PRIMARY CTA (writes status "pending")
//    EXISTS onboarding.completeStep         onboarding.ts:107   SECONDARY CTA, order guard :132-142
//    EXISTS documents.getAll                documents.ts:25     ledger rows, own-user scoped
//    EXISTS documents.getStats              documents.ts:63     filed / expiring / expired
//    EXISTS documents.delete                documents.ts:116    WITHDRAW — soft, audited, no inverse
//    EXISTS escorts.getCertificationStatus  escorts.ts:924      → resolver escorts.ts:487
//    EXISTS escorts.getProfile              escorts.ts:3081     equipment blob (read-only)
//
//  STUB, named, never invented — the four legs this screen refuses to fake:
//
//    · RECORDS (MVR + background). compliance.requestMVR EXISTS compliance.ts:2338
//      but is a NO-OP: it returns a synthetic `mvr_<ts>` id, writes NO row, holds
//      NO vendor, and is driverId-scoped rather than escort-self-service. There is
//      NO background-check procedure at all. This screen therefore paints gate 2
//      in its STUB register — a hard red barrier with NO SEAM on its face, never
//      green, never "in progress" — and offers no button that would pretend to
//      order one. Proposed:
//        escorts.requestRecordsCheck({consentAt, licenseState, licenseNumberLast4,
//          checkTypes:["mvr"|"criminal"|"psp"]})
//          → {checkId, status:"ordered", orderedAt, vendor, vendorRef}
//        escorts.getRecordsCheck({})
//          → {checkId, status: ordered|in_review|clear|flagged|failed, orderedAt,
//             completedAt, findings[], vendorRef}
//      over a new `escort_records_checks` table + WS ESCORT_RECORDS_CHECK_UPDATED.
//
//    · SUPERVISED RIDES (ESC-373 → ES-22). No procedure, no table, no mentor model
//      anywhere in frontend/server/routers. Gate 6 paints in the idle-STUB register
//      and the ES-22 exit card says NO PROCEDURE · NO TABLE on its face. Proposed:
//        escorts.getSupervisedProgress({}) → {required, logged, mentorAssigned,
//          rides:[{id,assignmentId,mentorUserId,mentorName,position,milesSupervised,
//          signedOffAt,verdict}]}
//        escorts.requestSupervisedRide({windowStart,windowEnd,position})
//        escorts.signOffSupervisedRide({rideId,verdict,notes})   // mentor side
//
//    · ESCORT COMPLIANCE PROFILE. onboarding.getRequiredDocuments routes
//      role != "DRIVER" into resolveCompanyCompliance (services/complianceEngine.ts:205),
//      where AUTO_LIABILITY / GENERAL_LIABILITY are CATALYST/OWNER_OPERATOR-only
//      (complianceEngine.ts:226-229) and MEDICAL_CERT is DRIVER-only (:463). For role
//      ESCORT the resolver returns ONLY role-agnostic tax + legal + home-state rows —
//      never a P/EVO, a DOT medical, an escort liability line or the equipment profile.
//      So `gateCoverage` and `gateCredentials` fall back to the escort's own uploaded
//      `documents` rows, and when neither the resolver nor the ledger can source a
//      requirement the gate reads NOT EVALUATED. It is never coloured green off an
//      empty resolver. Proposed: a `resolveEscortCompliance(profile)` branch emitting
//      PEVO_CERT / MEDICAL_CERT / AUTO_LIABILITY / GENERAL_LIABILITY /
//      ESCORT_EQUIPMENT_PROFILE, plus a role === "ESCORT" dispatch in
//      onboarding.getRequiredDocuments and getChecklist.
//
//    · DOCUMENT REVIEW STATE. `documents.status` is the enum
//      ["active","expired","pending"] and the table carries no reviewer,
//      reviewedAt or rejectionReason column. VERIFYING on this face is our LABEL
//      for the real value `pending` (uploadDocument writes exactly that at
//      onboarding.ts:529) and the ledger footer says so out loud. REJECTED has no
//      representation at all: the only rejection reason in the system is
//      application-grain `onboarding_progress.rejectionReason`, written by
//      onboarding.rejectApplicant (onboarding.ts:319, ADMIN/CATALYST only at :327).
//      This screen therefore renders a REJECTED chip only when that
//      application-grain reason exists, and dashes it to mark it unbacked.
//      Proposed: widen documents.status to pending|verifying|active|rejected|expired,
//      add reviewedByUserId / reviewedAt / rejectionReason, and add
//      documents.review({documentId, verdict, reason}) with a WS fan-out.
//
//    · EQUIPMENT WRITER. escorts.getProfile:3081 RETURNS `equipment`, but
//      escorts.updateProfile:3192 has NO equipment field in its input schema
//      (:3193-3207), and registration.registerEscort:1338 writes `equipmentList`
//      under users.metadata.REGISTRATION while getProfile reads
//      users.metadata.ESCORTPROFILE — two keys, no bridge. The 12 canonical item
//      keys mirrored below come from ESCORT_CHECKLIST_V1 escorts.ts:33 and are
//      enforced at assignment grain by escorts.submitVehicleCheck escorts.ts:1208.
//      Equipment is therefore READ-ONLY here: the gate reports what it can read and
//      offers no editor, because there is nothing to write to.
//
//  STAGE VOCABULARY, stated rather than hidden: onboarding.getSteps serves a FIXED,
//  role-agnostic seven-row array (profile · company · documents · payment ·
//  compliance · training · review, onboarding.ts:76-84) with no escort variant. The
//  six escort gates drawn here are a CLIENT-SIDE PROJECTION over that array joined
//  to the cert + document reads. The gate NAMES are ours; only the completion facts
//  are the server's, and the rail's footer says PROJECTION on the face.
//
//  DAY COUNTER: the SVG scenario reads "day 19 of 30". No read on the server exposes
//  an application-opened timestamp (onboardingProgress.createdAt is never returned)
//  and nothing defines a 30-day target, so this port shows DAY n counted from the
//  OLDEST documents.getAll uploadedAt, labelled SINCE FIRST FILING — and a bare dash
//  when there is nothing to count from. We do not print a deadline nobody set.
//
//  OFFLINE (§W): this pipeline STRADDLES the auth line and says so. Gate 1 runs on
//  registration.registerEscort registration.ts:1338 — an auditedPublicProcedure
//  (_core/trpc.ts:391) executed BEFORE a session exists, so it can be neither cached
//  nor queued and is never drawn as pending-on-device. Everything from gate 2
//  rightward is post-login. Mutations are ONLINE_ONLY (escort outbox not yet ported —
//  PLANNED per Encyclopedia v2); document upload IS a mutation and is therefore
//  ONLINE_ONLY, and NO queue badge is ever drawn. Reads = READ_CACHED(10m) via
//  EscortOfflineCache (key escort.onboarding.pipeline): while a snapshot paints, the
//  staleness line REPLACES the day counter, the rail dims, and both CTAs disable —
//  a stale CLEARED on an admission ladder is worse than showing nothing.
//
//  CHAIN: reads CLOSED. Document write ONE-SIDED — onboarding.uploadDocument:509
//  INSERTs the row and mutates users.metadata but emits NO WebSocket event and writes
//  NO audit row, so no reviewer surface learns a document landed; the missing half is
//  a reviewer fan-out (WS on WS_CHANNELS.USER + a recordAuditEvent row) at
//  onboarding.ts:509. Stage advance ONE-SIDED — completeStep:107 can flip the
//  application to pending_review with no event and no audit row, so the approver at
//  onboarding.ts:299 never learns anyone is waiting. Equipment ONE-SIDED — reader
//  exists, writer absent. Records-check SILENT. Supervised-ride SILENT.
//
//  RBAC — mixed, and the mix is the honest finding. escorts.* is escortProcedure
//  (escorts.ts:11 over roleProcedure(ROLES.ESCORT) _core/trpc.ts:212), row-scoped by
//  resolveEscortUserId escorts.ts:138. onboarding.* is isolatedProcedure
//  (_core/trpc.ts:468) and documents.* is auditedProtectedProcedure
//  (_core/trpc.ts:392) — BOTH any-authenticated-user, NOT escort-gated; each pins
//  rows to ctx.user.id server-side rather than to a role. No loads.rate, no shipper
//  margin, no other applicant's rows are bound anywhere in this file.
//
//  NAV: this surface belongs to the ME tab (the application lives beside the cert
//  wallet). EscortNavController.swift is single-writer owned and untouched here —
//  the manifest carries the nav entry this screen needs.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Wire projections (screen-local, private)

private struct ES20EmptyInput: Encodable {}

/// onboarding.getStatus · onboarding.ts:20
/// `userId` is intentionally omitted — the server echoes `ctx.user?.id`, whose
/// wire type varies, and this screen has no use for it.
private struct ES20Status: Codable, Equatable {
    let currentStep: Int?
    let totalSteps: Int?
    let completedSteps: [String]?
    let pendingSteps: [String]?
    let percentComplete: Int?
    let status: String?
}

/// onboarding.getSteps · onboarding.ts:71
private struct ES20Step: Codable, Identifiable, Equatable {
    let id: String
    let name: String?
    let order: Int?
    let title: String?
    let status: String?
}

/// onboarding.getProgress · onboarding.ts:387
private struct ES20Progress: Codable, Equatable {
    let step: Int?
    let totalSteps: Int?
    let percentage: Int?
    let completedSteps: Int?
    let estimatedTimeRemaining: String?
}

/// onboarding.getRequiredDocuments · onboarding.ts:424
private struct ES20RequiredDoc: Codable, Identifiable, Equatable {
    let id: String
    let type: String?
    let name: String?
    let required: Bool?
    let uploaded: Bool?
    let status: String?
    let expirationDate: String?
    let group: String?
    let priority: String?
}

/// documents.getAll · documents.ts:25
private struct ES20DocRow: Codable, Identifiable, Equatable {
    let id: String
    let name: String?
    let category: String?
    let status: String?
    let uploadedAt: String?
}

/// documents.getStats · documents.ts:63
private struct ES20DocStats: Codable, Equatable {
    let total: Int?
    let active: Int?
    let expiring: Int?
    let expired: Int?
}

/// escorts.getCertificationStatus · escorts.ts:924 → resolver escorts.ts:487
private struct ES20Cert: Codable, Identifiable, Equatable {
    let id: String
    let certType: String?
    let certNumber: String?
    let issuingState: String?
    let status: String?
    let expirationDate: String?
    let clearsStates: [String]?
}
private struct ES20CertStatus: Codable, Equatable {
    let total: Int?
    let active: Int?
    let expiringSoon: Int?
    let expired: Int?
    let statesCleared: [String]?
    let reciprocalStatesCleared: [String]?
    let certifications: [ES20Cert]?
}

/// `users.metadata.escortProfile.equipment` is an UNTYPED blob with no schema and
/// no writer (see STUB·equipment-writer above). We accept the two shapes that can
/// exist on disk today — a flat list of item keys, or a key→Bool map — and refuse
/// to invent a third. Anything else decodes to empty, which the gate reports as
/// NOT DECLARED rather than as zero-of-twelve.
private struct ES20EquipmentBlob: Codable, Equatable {
    let keys: [String]
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let arr = try? c.decode([String].self) { keys = arr; return }
        if let map = try? c.decode([String: Bool].self) {
            keys = map.filter { $0.value }.map { $0.key }.sorted(); return
        }
        keys = []
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(keys)
    }
}

/// escorts.getProfile · escorts.ts:3081 (partial — only what this surface reads)
private struct ES20Profile: Codable, Equatable {
    let name: String?
    let verificationStatus: String?
    let escortCompany: String?
    let preferredPosition: String?
    let equipment: ES20EquipmentBlob?
}

private struct ES20UploadReceipt: Decodable { let success: Bool?; let documentId: String? }
private struct ES20StepReceipt: Decodable { let success: Bool?; let stepId: String?; let error: String? }
private struct ES20DeleteReceipt: Decodable { let success: Bool?; let deletedId: String? }

/// The pipeline snapshot written to disk for READ_CACHED(10m).
private struct ES20Snapshot: Codable, Equatable {
    var status: ES20Status?
    var steps: [ES20Step] = []
    var progress: ES20Progress?
    var required: [ES20RequiredDoc] = []
    var docs: [ES20DocRow] = []
    var docStats: ES20DocStats?
    var cert: ES20CertStatus?
    var profile: ES20Profile?
}

// MARK: - Gate model (a CLIENT-SIDE PROJECTION — labelled as one on the face)

private enum ES20GateKind: Equatable {
    /// Arm raised, rail runs clean beneath.
    case cleared
    /// Barrier crosses the rail and kills it. `hard` means no seam exists to open it.
    case blocking(hard: Bool, idle: Bool)
    /// Notch hanging above the rail on a stem — the rail passes uninterrupted.
    case nonBlocking
    /// Unfilled ring: not earned.
    case terminus
}

private struct ES20Gate: Identifiable, Equatable {
    let id: String
    let name: String
    let state: String
    let kind: ES20GateKind
    /// Normalised position along the rail (0…1), mirroring the SVG stops.
    let x: Double

    var isBlocking: Bool { if case .blocking = kind { return true }; return false }
    var isCleared: Bool { kind == .cleared }
}

/// The canonical 12 escort equipment keys — mirrors ESCORT_CHECKLIST_V1 escorts.ts:33
/// verbatim. Held client-side ONLY to count a read-only profile blob against a known
/// denominator; nothing here writes them.
private let es20EquipmentKeys: [String] = [
    "height_pole", "oversize_load_signs", "warning_flags", "amber_beacons_or_lightbar",
    "cb_radio", "backup_comms", "fire_extinguisher", "first_aid_kit",
    "stop_slow_paddle", "safety_vest_hard_hat", "insurance_card_current", "spare_tire_jack",
]

// MARK: - Screen

struct EscortOnboardingRegistration: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    @State private var snap = ES20Snapshot()
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var busy = false
    /// nil == live. Non-nil replaces the day counter and disables both CTAs.
    @State private var cacheAge: TimeInterval?
    @State private var pickerPresented = false
    @State private var withdrawTarget: ES20DocRow?
    @State private var toast: String?

    private let cacheTTL: TimeInterval = 600          // READ_CACHED(10m)
    private let cacheKey = "escort.onboarding.pipeline"

    private var isDark: Bool { colorScheme == .dark }
    private var isSnapshot: Bool { cacheAge != nil }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && snap.status == nil {
                    loadingCard
                } else {
                    if let errorMessage {
                        Text(errorMessage).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    sectionLabel("PIPELINE · \(gates.count - 1) GATES TO SOLO",
                                 trailing: "\(blockingCount) BLOCKING · \(openCount) OPEN")
                    gateTrackCard
                    sectionLabel("NEXT STEP", trailing: "ONLINE ONLY · NO QUEUE")
                    nextStepCard
                    sectionLabel("DOCUMENT LEDGER",
                                 trailing: "\(snap.docStats?.total ?? snap.docs.count) FILED · \(blockingDocCount) BLOCKING")
                    documentLedger
                    sectionLabel("RECORDS LEG", trailing: "EVO-1049 §1")
                    recordsLegCard
                    handOffPair
                    esangRow
                }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { ctaBar }
        .overlay(alignment: .top) { toastBanner }
        .task { await load() }
        .eusoRefreshable { await load(forceNetwork: true) }
        .fileImporter(isPresented: $pickerPresented,
                      allowedContentTypes: [.pdf, .image, .item],
                      allowsMultipleSelection: false) { result in
            Task { await handlePicked(result) }
        }
        .confirmationDialog("Withdraw this document?",
                            isPresented: Binding(get: { withdrawTarget != nil },
                                                 set: { if !$0 { withdrawTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Withdraw · cannot be undone", role: .destructive) {
                if let t = withdrawTarget { Task { await withdraw(t) } }
            }
            Button("Keep it", role: .cancel) { withdrawTarget = nil }
        } message: {
            Text("A withdrawal is a soft delete: the row is stamped deletedAt and an audit row is written. There is no un-delete.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESCORT · ONBOARDING").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("0 → SOLO PIPELINE").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(ledgerLine).font(EType.mono(.micro))
                .foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            Text(headlineText).font(.system(size: 27, weight: .bold)).tracking(-0.6)
                .foregroundStyle(LinearGradient.diagonal).lineLimit(1).minimumScaleFactor(0.75)
            Text(subheadText).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            metaRow
            IridescentHairline()
        }
    }

    private var ledgerLine: String {
        let company = (snap.profile?.escortCompany?.isEmpty == false)
            ? snap.profile!.escortCompany!.uppercased() : "COMPANY NOT SET"
        let verdict = (snap.status?.status ?? snap.profile?.verificationStatus ?? "—")
            .replacingOccurrences(of: "_", with: " ").uppercased()
        return "APPLICATION · \(company) · \(verdict)"
    }

    private var headlineText: String {
        if blockingCount == 0 && !gates.isEmpty { return "0 gates block solo" }
        return "\(blockingCount) gate\(blockingCount == 1 ? "" : "s") block solo"
    }

    private var subheadText: String {
        let stage = currentGateIndex + 1
        let total = max(1, gates.count - 1)
        let hard = gates.contains { if case .blocking(let h, _) = $0.kind { return h }; return false }
        return "Stage \(stage) of \(total) · \(hard ? "records has no vendor seam" : "no hard stop on the rail")"
    }

    /// APPLICANT is the only status this account holds. A declared preferred
    /// position is NOT a certification, so it wears a dashed outline rather than a
    /// filled position badge — the badge vocabulary without the claim.
    private var metaRow: some View {
        HStack(spacing: Space.s2) {
            Text("APPLICANT").font(.system(size: 10, weight: .heavy)).tracking(0.5)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Brand.warning.opacity(isDark ? 0.24 : 0.16)))

            if let declared = declaredPositionLabel {
                Text("\(declared) · DECLARED").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.escort)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(Brand.escort.opacity(0.45),
                                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }

            // The honesty law: a snapshot NEVER wears a live-looking stamp.
            if let cacheAge {
                Text(EscortOfflineCache.stalenessLine(age: cacheAge))
                    .font(.system(size: 10.5, weight: .semibold).monospaced())
                    .foregroundStyle(Brand.warning)
            } else {
                Text(dayLine).font(.system(size: 10.5, weight: .semibold).monospaced())
                    .foregroundStyle(palette.textPrimary)
            }

            Spacer(minLength: 4)
            Text(snap.profile?.name ?? "—").font(.system(size: 10.5).monospaced())
                .foregroundStyle(palette.textTertiary).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var declaredPositionLabel: String? {
        guard let p = snap.profile?.preferredPosition, !p.isEmpty else { return nil }
        switch p.lowercased() {
        case "chase", "rear": return "CHASE"
        case "steer":         return "STEER"
        case "high_pole", "highpole", "pole": return "HIGH-POLE"
        case "lead":          return "LEAD"
        default:              return p.uppercased()
        }
    }

    /// No read exposes an application-opened timestamp and nothing defines a
    /// 30-day target, so we count from the oldest filing we can actually see —
    /// and print a dash when there is nothing to count from.
    private var dayLine: String {
        guard let oldest = snap.docs.compactMap({ parseDay($0.uploadedAt) }).min() else {
            return "DAY — · NO FILINGS"
        }
        let days = max(0, Int(Date().timeIntervalSince(oldest) / 86_400))
        return "DAY \(days) · SINCE FIRST FILING"
    }

    private func sectionLabel(_ leading: String, trailing: String) -> some View {
        HStack {
            Text(leading).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
            Text(trailing).font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var loadingCard: some View {
        Text("Reading the application…")
            .font(EType.caption).foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
    }

    // MARK: Gate track (HERO)

    private var gateTrackCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            gateRail.frame(height: 84)
            Rectangle().fill(palette.borderFaint).frame(height: 1)
                .padding(.horizontal, 12).padding(.top, 4)
            statQuartet.padding(.top, 8)
            HStack(alignment: .top, spacing: 6) {
                Text(equipmentLine).font(.system(size: 6, weight: .bold).monospaced())
                    .foregroundStyle(palette.textTertiary).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                Text("GATE NAMES ARE A CLIENT PROJECTION")
                    .font(.system(size: 6, weight: .bold).monospaced())
                    .foregroundStyle(palette.textTertiary).lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .opacity(isSnapshot ? 0.6 : 1)
    }

    private var gateRail: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let railY: CGFloat = 46
            let firstBlocked = gates.first(where: { $0.isBlocking })
            let deadStart = CGFloat(firstBlocked?.x ?? 0.94) * w
            let clearedStart = CGFloat(gates.first?.x ?? 0) * w

            ZStack(alignment: .topLeading) {
                Capsule().fill(LinearGradient.primary)
                    .frame(width: max(0, deadStart - clearedStart), height: 3)
                    .offset(x: clearedStart, y: railY - 1.5)

                Path { p in
                    p.move(to: CGPoint(x: deadStart, y: railY))
                    p.addLine(to: CGPoint(x: w * 0.94, y: railY))
                }
                .stroke(palette.textTertiary.opacity(0.45),
                        style: StrokeStyle(lineWidth: 2, dash: [4, 4]))

                ForEach(gates) { gate in gateGlyph(gate, w: w, railY: railY) }

                if let blocked = firstBlocked {
                    let bx = CGFloat(blocked.x) * w
                    Text("YOU ARE HERE").font(.system(size: 6, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(Brand.blue)
                        .frame(width: 70, alignment: .trailing)
                        .offset(x: bx - 89, y: railY - 16)
                    ES20Wedge().fill(LinearGradient.primary)
                        .frame(width: 10, height: 12)
                        .offset(x: bx - 17, y: railY - 6)
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 4)
    }

    @ViewBuilder
    private func gateGlyph(_ gate: ES20Gate, w: CGFloat, railY: CGFloat) -> some View {
        let x = CGFloat(gate.x) * w
        ZStack(alignment: .topLeading) {
            switch gate.kind {
            case .cleared:
                Capsule().fill(Brand.success.opacity(0.55)).frame(width: 3, height: 13)
                    .offset(x: x - 1.5, y: 22)
                ZStack {
                    Circle().fill(Brand.success).frame(width: 14, height: 14)
                    Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .offset(x: x - 7, y: railY - 7)

            case .blocking(let hard, let idle):
                let tone: Color = hard ? Brand.danger : (idle ? palette.textTertiary : Brand.warning)
                let h: CGFloat = hard ? 36 : 28
                let top: CGFloat = hard ? 28 : 32
                let capW: CGFloat = hard ? 14 : 12
                let capH: CGFloat = hard ? 3 : 2.5
                Capsule().fill(tone.opacity(hard ? 1 : 0.65)).frame(width: capW, height: capH)
                    .offset(x: x - capW / 2, y: top)
                Capsule().fill(tone).frame(width: 3, height: h)
                    .offset(x: x - 1.5, y: top)
                Capsule().fill(tone.opacity(hard ? 1 : 0.65)).frame(width: capW, height: capH)
                    .offset(x: x - capW / 2, y: top + h - capH)

            case .nonBlocking:
                Text("NON-BLOCKING").font(.system(size: 5.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(Brand.warning)
                    .frame(width: 44, height: 14)
                    .background(Capsule().fill(Brand.warning.opacity(isDark ? 0.18 : 0.10)))
                    .overlay(Capsule().strokeBorder(Brand.warning.opacity(0.45)))
                    .offset(x: x - 22, y: 16)
                Rectangle().fill(Brand.warning.opacity(0.5)).frame(width: 1.2, height: 12)
                    .offset(x: x - 0.6, y: 30)
                Circle().fill(palette.bgCard)
                    .overlay(Circle().strokeBorder(Brand.warning, lineWidth: 1.5))
                    .frame(width: 8, height: 8)
                    .offset(x: x - 4, y: railY - 4)

            case .terminus:
                Circle().fill(palette.bgCard)
                    .overlay(Circle().strokeBorder(LinearGradient.primary, lineWidth: 2.5))
                    .frame(width: 16, height: 16)
                    .offset(x: x - 8, y: railY - 8)
                Image(systemName: "lock.fill").font(.system(size: 6, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                    .offset(x: x - 3.5, y: railY - 4)
            }

            VStack(spacing: 3) {
                Text(gate.name).font(.system(size: 6.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                Text(gate.state).font(.system(size: 6, weight: .bold).monospaced())
                    .foregroundStyle(stateInk(gate)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(width: 58)
            .offset(x: x - 29, y: railY + 15)
        }
    }

    private func stateInk(_ gate: ES20Gate) -> Color {
        switch gate.kind {
        case .cleared: return Brand.success
        case .blocking(let hard, let idle):
            return hard ? Brand.danger : (idle ? palette.textTertiary : Brand.warning)
        case .nonBlocking: return Brand.warning
        case .terminus: return palette.textTertiary
        }
    }

    private var statQuartet: some View {
        HStack(spacing: 0) {
            statCell("CLEARED", "\(clearedCount) / \(max(1, gates.count - 1))", Brand.success)
            statDivider
            statCell("BLOCKING", "\(blockingCount)", Brand.danger)
            statDivider
            statCell("FILED", "\(snap.docStats?.total ?? snap.docs.count)", palette.textPrimary)
            statDivider
            statCell("STEPS",
                     "\(snap.status?.completedSteps?.count ?? 0) / \(snap.status?.totalSteps ?? 7)",
                     Brand.blue)
        }
        .padding(.horizontal, 12)
    }

    private var statDivider: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 26)
    }

    private func statCell(_ label: String, _ value: String, _ ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 15, weight: .heavy).monospaced())
                .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 2)
    }

    // MARK: Next step · what it costs

    private var nextStepCard: some View {
        HStack(spacing: 0) {
            Rectangle().fill(LinearGradient.diagonal).frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("WHAT THE NEXT STEP COSTS").font(.system(size: 8, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 0)
                    Text("IRREVERSIBLE").font(.system(size: 7, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.warning)
                }
                Text(nextStepTitle).font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary).padding(.top, 8)
                    .lineLimit(2).minimumScaleFactor(0.75)
                Text(nextStepContext).font(.system(size: 8, weight: .bold).monospaced())
                    .foregroundStyle(palette.textSecondary).padding(.top, 6)
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text("COST · WITHDRAWING IS PERMANENT — THE APPLICATION IS MARKED WITHDRAWN AND STAMPED IN THE AUDIT TRAIL. NO UNDO.")
                    .font(.system(size: 7, weight: .bold).monospaced())
                    .foregroundStyle(Brand.warning).padding(.top, 5)
                    .lineLimit(1).minimumScaleFactor(0.55)
                Text("COST · CLOSING A STAGE CANNOT BE UNDONE — STAGES MUST BE COMPLETED IN ORDER.")
                    .font(.system(size: 7, weight: .bold).monospaced())
                    .foregroundStyle(Brand.warning).padding(.top, 5)
                    .lineLimit(1).minimumScaleFactor(0.55)
            }
            .padding(.horizontal, 13).padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .opacity(isSnapshot ? 0.6 : 1)
    }

    private var nextStepTitle: String {
        if let target = uploadTarget {
            return "Upload \(prettyName(target)), then complete stage"
        }
        if currentStepId != nil { return "Complete the current stage" }
        return "Nothing on this phone advances the rail"
    }

    /// The trailing clause is the SERVER's own estimate (onboarding.getProgress
    /// .estimatedTimeRemaining, onboarding.ts:415) — a step-count derivation, not a
    /// promised date, which is why it is quoted as an estimate and dropped when absent.
    private var nextStepContext: String {
        var tail = ""
        if let est = snap.progress?.estimatedTimeRemaining, !est.isEmpty {
            tail = " · ESTIMATE \(est.uppercased())"
        }
        guard let gate = gates.first(where: { $0.isBlocking }) else {
            return "NO BLOCKING GATE ON THE RAIL\(tail)"
        }
        if case .blocking(let hard, _) = gate.kind, hard {
            return "GATE \(gateOrdinal(gate)) \(gate.name) · \(gate.state) · NOT CLEARABLE HERE\(tail)"
        }
        return "GATE \(gateOrdinal(gate)) \(gate.name) · \(gate.state)\(tail)"
    }

    // MARK: Document ledger

    private var documentLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            if ledgerRows.isEmpty {
                Text("No documents filed yet. The rail cannot clear a gate it cannot read.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 14)
            } else {
                ForEach(Array(ledgerRows.enumerated()), id: \.element.id) { idx, row in
                    if idx > 0 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 12)
                    }
                    docRow(row)
                }
            }
            Text("STATUS ENUM = active · expired · pending — VERIFYING IS OUR LABEL FOR pending; REJECTED HAS NO COLUMN")
                .font(.system(size: 6.5, weight: .bold).monospaced())
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
                .lineLimit(1).minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .opacity(isSnapshot ? 0.6 : 1)
    }

    private func docRow(_ row: ES20LedgerRow) -> some View {
        HStack(spacing: 10) {
            Text(row.badge).font(.system(size: 9, weight: .heavy).monospaced())
                .foregroundStyle(.white)
                .frame(width: 32, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(row.tint))
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title).font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.72)
                Text(row.detail).font(.system(size: 7.5, weight: .bold).monospaced())
                    .foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 4)
            docChip(row)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isSnapshot, let src = row.source else { return }
            withdrawTarget = src
        }
    }

    /// A SOLID chip means the word maps to a real `documents.status` value.
    /// A DASHED chip means the word has no column behind it.
    private func docChip(_ row: ES20LedgerRow) -> some View {
        Text(row.chip)
            .font(.system(size: 8, weight: .heavy).monospaced())
            .foregroundStyle(row.tint)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(width: 64, height: 18)
            .background(Capsule().fill(row.unbacked ? Color.clear : row.tint.opacity(isDark ? 0.22 : 0.14)))
            .overlay(Capsule().strokeBorder(row.unbacked ? row.tint.opacity(0.6) : Color.clear,
                                            style: StrokeStyle(lineWidth: 1, dash: row.unbacked ? [3, 2] : [])))
    }

    // MARK: Records leg — drawn as the gap it is

    private var recordsLegCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("GATE 2 · MVR + BACKGROUND CHECK").font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("NOT AVAILABLE · NO CHECK PROVIDER CONNECTED").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.danger)
            }
            Text("NOTHING IS FILED · THIS REQUEST RETURNS A PLACEHOLDER REFERENCE AND ORDERS NOTHING")
                .font(.system(size: 6.8, weight: .bold).monospaced())
                .foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.6)
            Text("PLANNED · CONSENT + LICENSE STATE + LAST 4 → A REAL CHECK REFERENCE AND STATUS")
                .font(.system(size: 6.5, weight: .bold).monospaced())
                .foregroundStyle(palette.textTertiary).lineLimit(1).minimumScaleFactor(0.55)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg - 2, style: .continuous)
            .strokeBorder(palette.textTertiary.opacity(0.5),
                          style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .allowsHitTesting(false)
    }

    // MARK: Hand-offs

    private var handOffPair: some View {
        HStack(spacing: 12) {
            handOffCard(title: "ES-08 CERT RECIPROCITY",
                        detail: "STATE APPLICATIONS · \(clearedStateCount) / 51",
                        micro: "STATE CERTIFICATE UPLOAD · LIVE",
                        accent: Brand.blue, dashed: false)
            handOffCard(title: "ES-22 SUPERVISED RIDE",
                        detail: "0 OF 3 · MENTOR UNASSIGNED",
                        micro: "NOT AVAILABLE YET · NOTHING IS RECORDED",
                        accent: palette.textTertiary, dashed: true)
        }
    }

    private func handOffCard(title: String, detail: String, micro: String,
                             accent: Color, dashed: Bool) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(accent).frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 9.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.system(size: 7.5, weight: .bold).monospaced())
                    .foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.6)
                Text(micro).font(.system(size: 6.3, weight: .bold).monospaced())
                    .foregroundStyle(palette.textTertiary).lineLimit(1).minimumScaleFactor(0.55)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textTertiary).padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg - 2, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg - 2, style: .continuous)
            .strokeBorder(dashed ? palette.textTertiary.opacity(0.5) : palette.borderFaint,
                          style: StrokeStyle(lineWidth: 1, dash: dashed ? [5, 4] : [])))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg - 2, style: .continuous))
        .allowsHitTesting(!dashed)
    }

    // MARK: ESANG

    private var esangRow: some View {
        HStack(spacing: 0) {
            Rectangle().fill(LinearGradient.diagonal).frame(width: 3)
            HStack(spacing: 10) {
                ZStack(alignment: .topLeading) {
                    Circle().fill(LinearGradient.diagonal).frame(width: 18, height: 18)
                    Circle().fill(Color.white.opacity(0.45)).frame(width: 7, height: 7)
                        .offset(x: 1.5, y: 1.5)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("ESANG").font(.system(size: 9.5, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(LinearGradient.primary)
                        Text(esangHeadline).font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Text(esangBody).font(.system(size: 8, weight: .medium))
                        .foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg - 2, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg - 2, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg - 2, style: .continuous))
    }

    /// ESANG only speaks to what the reads can source. With no upload target it
    /// says so rather than inventing an action.
    private var esangHeadline: String {
        guard let target = uploadTarget else { return "· No filing on this phone moves the rail" }
        return "· \(prettyName(target)) is the cheapest gate today"
    }
    private var esangBody: String {
        guard uploadTarget != nil else {
            return "Records has no vendor connection yet, and supervised rides cannot be filed from here at all."
        }
        return "File it and the gate ahead of you drops. Records still cannot clear here."
    }

    // MARK: CTA bar (both ONLINE_ONLY — never a queue badge)

    private var uploadDisabled: Bool { busy || isSnapshot || uploadTarget == nil }
    private var completeDisabled: Bool { busy || isSnapshot || currentStepId == nil }

    private var ctaBar: some View {
        HStack(spacing: Space.s2) {
            Button { pickerPresented = true } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: "arrow.up").font(.system(size: 12, weight: .heavy))
                    Text(uploadTarget == nil ? "NOTHING TO FILE"
                                             : "UPLOAD \(prettyName(uploadTarget!).uppercased())")
                        .font(.system(size: 12.5, weight: .heavy)).tracking(0.3)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(Capsule().fill(uploadDisabled
                                           ? AnyShapeStyle(palette.textTertiary)
                                           : AnyShapeStyle(LinearGradient.primary)))
            }
            .buttonStyle(.plain).disabled(uploadDisabled)

            Button { Task { await completeStage() } } label: {
                Text("COMPLETE STAGE")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(Brand.blue)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(width: 138, height: 42)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(Brand.blue.opacity(0.55), lineWidth: 1.5))
            }
            .buttonStyle(.plain).disabled(completeDisabled)
            .opacity(completeDisabled ? 0.5 : 1)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var toastBanner: some View {
        if let t = toast {
            Text(t)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Brand.blue.opacity(0.92), in: Capsule())
                .padding(.top, 10)
                .onAppear {
                    Task {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        await MainActor.run { toast = nil }
                    }
                }
        }
    }

    // MARK: - Gate projection (derived from the reads — nothing seeded)

    private var gates: [ES20Gate] {
        let xs: [Double] = [0.0600, 0.2075, 0.3525, 0.5000, 0.6475, 0.7925, 0.9400]
        var out: [ES20Gate] = []

        // 1 · REGISTER — the only gate whose completion the server states directly.
        let completed = Set(snap.status?.completedSteps ?? [])
        let registered = completed.contains("profile")
        out.append(ES20Gate(id: "register", name: "REGISTER",
                            state: registered ? "CLEARED" : "OPEN",
                            kind: registered ? .cleared : .blocking(hard: false, idle: false),
                            x: xs[0]))

        // 2 · RECORDS — STUB. No read exists, so this can never be green.
        out.append(ES20Gate(id: "records", name: "RECORDS", state: "NOT AVAILABLE · NO SOURCE",
                            kind: .blocking(hard: true, idle: false), x: xs[1]))

        // 3 · CREDENTIALS — P/EVO from escort_certifications + DOT medical from documents.
        let hasCert = (snap.cert?.active ?? 0) > 0
        let medical = documentState(matching: ["MEDICAL", "MED_CARD", "DOT_PHYSICAL"])
        let credHave = (hasCert ? 1 : 0) + (medical == .active ? 1 : 0)
        out.append(ES20Gate(id: "creds", name: "CREDENTIALS",
                            state: "\(credHave) OF 2",
                            kind: credHave >= 2 ? .cleared : .blocking(hard: false, idle: false),
                            x: xs[2]))

        // 4 · COVERAGE — auto + general liability. When neither the requirement
        // resolver nor the ledger can source them we say NOT EVALUATED. We never
        // colour this green off an empty resolver.
        let auto = documentState(matching: ["AUTO_LIABILITY", "AUTO LIAB"])
        let general = documentState(matching: ["GENERAL_LIABILITY", "GENERAL LIAB"])
        let covHave = (auto == .active ? 1 : 0) + (general == .active ? 1 : 0)
        let covKnown = auto != .absent || general != .absent
            || requiredIds.contains(where: { $0.contains("LIABILITY") })
        out.append(ES20Gate(id: "coverage", name: "COVERAGE",
                            state: covKnown ? "\(covHave) OF 2" : "NOT EVALUATED",
                            kind: covKnown && covHave >= 2 ? .cleared
                                                           : .blocking(hard: false, idle: !covKnown),
                            x: xs[3]))

        // 5 · EQUIPMENT — read-only profile blob against the canonical 12 keys.
        // Non-blocking for APPROVAL; it blocks the first assignment, not this ladder.
        out.append(ES20Gate(id: "equipment", name: "EQUIPMENT", state: equipmentState,
                            kind: .nonBlocking, x: xs[4]))

        // 6 · SUPERVISED — STUB. No procedure, no table, no mentor.
        out.append(ES20Gate(id: "supervised", name: "SUPERVISED", state: "NOT AVAILABLE · 0 LOGGED",
                            kind: .blocking(hard: false, idle: true), x: xs[5]))

        // 7 · SOLO terminus.
        out.append(ES20Gate(id: "solo", name: "SOLO", state: "LOCKED", kind: .terminus, x: xs[6]))
        return out
    }

    private var clearedCount: Int { gates.filter { $0.isCleared }.count }
    private var blockingCount: Int { gates.filter { $0.isBlocking }.count }
    private var openCount: Int { gates.filter { if case .nonBlocking = $0.kind { return true }; return false }.count }
    private var currentGateIndex: Int {
        gates.firstIndex(where: { $0.isBlocking }) ?? max(0, gates.count - 2)
    }
    private func gateOrdinal(_ gate: ES20Gate) -> Int {
        (gates.firstIndex(where: { $0.id == gate.id }) ?? 0) + 1
    }

    private var equipmentState: String {
        guard let keys = snap.profile?.equipment?.keys, !keys.isEmpty else { return "NOT DECLARED" }
        let known = Set(es20EquipmentKeys)
        let declared = Set(keys.map { $0.lowercased() }).intersection(known).count
        return "\(declared) OF \(es20EquipmentKeys.count)"
    }

    private var equipmentLine: String {
        guard let keys = snap.profile?.equipment?.keys, !keys.isEmpty else {
            return "EQUIPMENT NOT DECLARED · NO WRITER EXISTS"
        }
        let declared = Set(keys.map { $0.lowercased() })
        let missing = es20EquipmentKeys.filter { !declared.contains($0) }
            .prefix(2).map { $0.replacingOccurrences(of: "_", with: "-").uppercased() }
        if missing.isEmpty { return "EQUIPMENT \(es20EquipmentKeys.count)/\(es20EquipmentKeys.count) DECLARED" }
        return "EQUIPMENT · MISSING \(missing.joined(separator: ", "))"
    }

    private var clearedStateCount: Int {
        (snap.cert?.statesCleared?.count ?? 0) + (snap.cert?.reciprocalStatesCleared?.count ?? 0)
    }

    // MARK: - Document projection

    private enum ES20DocVerdict: Equatable { case active, verifying, expired, rejected, absent }

    private var requiredIds: [String] {
        snap.required.flatMap { [$0.id.uppercased(), ($0.type ?? "").uppercased()] }
    }

    /// One resolution for a document class across BOTH readable sources: the
    /// requirement resolver (which knows expiry) and the escort's own ledger rows.
    private func documentState(matching needles: [String]) -> ES20DocVerdict {
        let hits = needles.map { $0.uppercased() }
        func matches(_ s: String?) -> Bool {
            guard let s = s?.uppercased() else { return false }
            return hits.contains { s.contains($0) }
        }

        if let req = snap.required.first(where: { matches($0.id) || matches($0.type) }) {
            if req.uploaded == true {
                if let exp = parseDay(req.expirationDate), exp < Date() { return .expired }
                return (req.status ?? "").lowercased() == "pending" ? .verifying : .active
            }
        }
        if let row = snap.docs.first(where: { matches($0.category) || matches($0.name) }) {
            switch (row.status ?? "").lowercased() {
            case "pending":  return .verifying
            case "expired":  return .expired
            case "active":   return .active
            default:         return .verifying
            }
        }
        return .absent
    }

    private struct ES20LedgerRow: Identifiable {
        let id: String
        let badge: String
        let title: String
        let detail: String
        let chip: String
        let tint: Color
        let unbacked: Bool
        let source: ES20DocRow?
    }

    private var ledgerRows: [ES20LedgerRow] {
        // The escort's own filings, newest first, joined to whatever expiry the
        // requirement resolver can supply for the same type.
        var rows: [ES20LedgerRow] = snap.docs.prefix(6).map { row in
            let raw = (row.status ?? "active").lowercased()
            let verdict: ES20DocVerdict = raw == "pending" ? .verifying
                                        : raw == "expired" ? .expired : .active
            let req = snap.required.first {
                ($0.type ?? "").caseInsensitiveCompare(row.category ?? "") == .orderedSame
            }
            var bits: [String] = []
            if let up = row.uploadedAt, !up.isEmpty { bits.append("FILED \(up)") }
            bits.append("status=\(raw)")
            if let exp = req?.expirationDate, !exp.isEmpty { bits.append("EXP \(String(exp.prefix(10)))") }
            return ES20LedgerRow(
                id: row.id,
                badge: String((row.category ?? "DOC").uppercased().prefix(3)),
                title: row.name ?? row.category ?? "Document",
                detail: bits.joined(separator: " · "),
                chip: chipWord(verdict),
                tint: chipTint(verdict),
                unbacked: false,
                source: row
            )
        }

        // Certifications live in escort_certifications, not documents — they carry
        // their own reach and their own expiry, so they get their own rows.
        for c in (snap.cert?.certifications ?? []).prefix(3) {
            let expired = (c.status ?? "").lowercased() == "expired"
            let reach = c.clearsStates?.count ?? 0
            var bits: [String] = [(c.status ?? "active").uppercased()]
            if let e = c.expirationDate, !e.isEmpty { bits.append("EXPIRES \(String(e.prefix(10)))") }
            if reach > 0 { bits.append("CLEARS \(reach) STATES") }
            rows.append(ES20LedgerRow(
                id: "cert-\(c.id)",
                badge: (c.issuingState ?? "??").uppercased(),
                title: "\((c.certType ?? "CERT").uppercased()) · \(c.certNumber ?? "—")",
                detail: bits.joined(separator: " · "),
                chip: expired ? "EXPIRED" : "ACTIVE",
                tint: expired ? Brand.danger : Brand.success,
                unbacked: false,
                source: nil          // certs are not documents rows — no withdraw path
            ))
        }

        // A REJECTED chip is drawn ONLY when the application-grain rejection reason
        // actually exists, and it is dashed because no document-grain column backs it.
        if (snap.status?.status ?? "").lowercased() == "rejected" {
            rows.insert(ES20LedgerRow(
                id: "application-rejection",
                badge: "APP",
                title: "Application review",
                detail: "REJECTED AT APPLICATION GRAIN · REASON NOT EXPOSED TO THIS READ",
                chip: "REJECTED",
                tint: Brand.danger,
                unbacked: true,
                source: nil
            ), at: 0)
        }
        return rows
    }

    private func chipWord(_ v: ES20DocVerdict) -> String {
        switch v {
        case .active: return "ACTIVE"
        case .verifying: return "VERIFYING"
        case .expired: return "EXPIRED"
        case .rejected: return "REJECTED"
        case .absent: return "MISSING"
        }
    }
    private func chipTint(_ v: ES20DocVerdict) -> Color {
        switch v {
        case .active: return Brand.success
        case .verifying: return Brand.warning
        case .expired, .rejected: return Brand.danger
        case .absent: return Brand.neutral
        }
    }

    private var blockingDocCount: Int {
        ledgerRows.filter { $0.chip == "EXPIRED" || $0.chip == "REJECTED" }.count
    }

    /// The first CRITICAL/HIGH requirement the escort has not satisfied. Comes
    /// straight off onboarding.getRequiredDocuments — when the resolver returns
    /// nothing for role ESCORT (the named gap above) there is honestly nothing to
    /// upload from here, and the CTA says so rather than guessing a type.
    private var uploadTarget: ES20RequiredDoc? {
        snap.required.first { req in
            if req.uploaded != true { return true }
            if let exp = parseDay(req.expirationDate), exp < Date() { return true }
            return false
        }
    }

    private func prettyName(_ req: ES20RequiredDoc) -> String {
        req.name ?? (req.type ?? req.id).replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// The step the server itself says is current — never a client guess.
    private var currentStepId: String? {
        if let s = snap.steps.first(where: { ($0.status ?? "") == "in_progress" }) { return s.id }
        guard let order = snap.status?.currentStep else { return nil }
        return snap.steps.first(where: { $0.order == order })?.id
    }

    // MARK: - Data plumbing (READ_CACHED(10m) · mutations ONLINE_ONLY)

    private func softQuery<T: Decodable, I: Encodable>(_ path: String, _ input: I) async -> T? {
        do { let v: T = try await EusoTripAPI.shared.query(path, input: input); return v }
        catch { return nil }
    }

    private func load(forceNetwork: Bool = false) async {
        if snap.status == nil { await MainActor.run { loading = true } }
        do {
            // Primary reads — the rail cannot honestly draw without these.
            async let status: ES20Status = EusoTripAPI.shared.query(
                "onboarding.getStatus", input: ES20EmptyInput())
            async let steps: [ES20Step] = EusoTripAPI.shared.query(
                "onboarding.getSteps", input: ES20EmptyInput())
            async let cert: ES20CertStatus = EusoTripAPI.shared.query(
                "escorts.getCertificationStatus", input: ES20EmptyInput())

            var next = ES20Snapshot()
            next.status = try await status
            next.steps = try await steps
            next.cert = try await cert

            // Secondary reads — a failure degrades one band, not the whole rail.
            next.progress = await softQuery("onboarding.getProgress", ES20EmptyInput())
            next.required = await softQuery("onboarding.getRequiredDocuments", ES20EmptyInput()) ?? []
            next.docs = await softQuery("documents.getAll", ES20DocQueryInput()) ?? []
            next.docStats = await softQuery("documents.getStats", ES20EmptyInput())
            next.profile = await softQuery("escorts.getProfile", ES20EmptyInput())

            await MainActor.run {
                snap = next
                cacheAge = nil
                errorMessage = nil
                loading = false
            }
            EscortOfflineCache.store(next, key: cacheKey)
        } catch {
            // READ_CACHED(10m): replay the last good snapshot, say its age out
            // loud, and refuse it entirely once the ttl is blown.
            if !forceNetwork,
               let hit = EscortOfflineCache.load(ES20Snapshot.self, key: cacheKey, ttl: cacheTTL) {
                await MainActor.run {
                    snap = hit.value
                    cacheAge = hit.age
                    loading = false
                    errorMessage = nil
                }
            } else {
                await MainActor.run {
                    cacheAge = nil
                    loading = false
                    errorMessage = "Couldn't read the application. Pull to retry."
                }
            }
        }
    }

    private struct ES20DocQueryInput: Encodable { var search: String? = nil; var category: String? = nil }

    // MARK: Mutations — ONLINE_ONLY, no queue, no optimistic gate flip

    private struct ES20UploadInput: Encodable {
        let type: String
        let fileUrl: String
        let fileName: String
        let expirationDate: String?
    }

    private func handlePicked(_ result: Result<[URL], Error>) async {
        guard let target = uploadTarget else { return }
        switch result {
        case .failure(let err):
            await MainActor.run { toast = "That file couldn't be opened. Pick it again, or choose another copy." }
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            await MainActor.run { busy = true }
            do {
                let data = try Data(contentsOf: url)
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                // Same wire the house upload uses: a base64 data URL in the
                // fileUrl text column. There is no blob/presign seam in the tree.
                let dataURL = "data:\(mime);base64,\(data.base64EncodedString())"
                let receipt: ES20UploadReceipt = try await EusoTripAPI.shared.mutation(
                    "onboarding.uploadDocument",
                    input: ES20UploadInput(type: target.type ?? target.id,
                                           fileUrl: dataURL,
                                           fileName: url.lastPathComponent,
                                           expirationDate: nil))
                await MainActor.run {
                    busy = false
                    toast = receipt.success == true
                        ? "Filed · it lands as pending, not approved"
                        : "Filed"
                }
                await load(forceNetwork: true)
            } catch {
                await MainActor.run {
                    busy = false
                    toast = "Upload needs a connection — escort writes are not queued yet."
                }
            }
        }
    }

    private struct ES20StepInput: Encodable { let stepId: String }

    private func completeStage() async {
        guard let stepId = currentStepId else { return }
        await MainActor.run { busy = true }
        do {
            let receipt: ES20StepReceipt = try await EusoTripAPI.shared.mutation(
                "onboarding.completeStep", input: ES20StepInput(stepId: stepId))
            await MainActor.run {
                busy = false
                // The server refuses out-of-order steps by throwing; a false
                // success with an error string is surfaced verbatim, not swallowed.
                toast = receipt.success == true ? "Stage \(stepId) closed · this cannot be undone"
                                                : (receipt.error ?? "Stage not closed")
            }
            await load(forceNetwork: true)
        } catch {
            await MainActor.run {
                busy = false
                toast = "Stage changes need a connection — escort writes are not queued yet."
            }
        }
    }

    private struct ES20DeleteInput: Encodable { let id: String }

    private func withdraw(_ row: ES20DocRow) async {
        await MainActor.run { busy = true; withdrawTarget = nil }
        do {
            let _: ES20DeleteReceipt = try await EusoTripAPI.shared.mutation(
                "documents.delete", input: ES20DeleteInput(id: row.id))
            await MainActor.run { busy = false; toast = "Withdrawn · stamped in the audit trail, cannot be undone" }
            await load(forceNetwork: true)
        } catch {
            await MainActor.run {
                busy = false
                toast = "Withdrawals need a connection — escort writes are not queued yet."
            }
        }
    }

    // MARK: Utilities

    private func parseDay(_ s: String?) -> Date? {
        guard let s, !s.isEmpty, s != "—" else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        if let d = f.date(from: String(s.prefix(10))) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }
}

// MARK: - Glyph

/// The YOU wedge — a right-pointing marker that reads as pressure against the barrier.
private struct ES20Wedge: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Registered surface wrapper

struct EscortOnboardingRegistrationScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortOnboardingRegistration()
        } nav: {
            // Escort role enum TRIP · COMMS | PERMIT · ME — the application lives
            // under ME beside the cert wallet, mirroring ES-08 and ES-12.
            BottomNav(
                leading: EscortNavRoute.leading(current: .me),
                trailing: EscortNavRoute.trailing(current: .me),
                orbState: .idle
            )
        }
    }
}

#Preview("ES-20 · Onboarding & Registration · Dark") {
    EscortOnboardingRegistrationScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("ES-20 · Onboarding & Registration · Light") {
    EscortOnboardingRegistrationScreen(theme: Theme.light).preferredColorScheme(.light)
}
