//
//  198B_DriverLivenessChallenge.swift
//  EusoTrip — Screen 198B · Liveness Challenge (LIVE-wired · CAMERA archetype)
//
//  Purpose: an active anti-spoof challenge + telemetry that defeats
//  photo / video / mask spoof before the gate-identity bind (198).
//
//  Wiring manifest:
//    kyc.runLiveness       EXISTS · kyc.ts:215
//      input { userId? } → { score, livenessPassed }; writes a
//      kyc_verifications row + audit; a null verdict routes to review.
//    kyc.getVerifications  EXISTS · kyc.ts:431
//      input { userId?, limit } → { verifications[] } — the driver's own
//      verification history.
//  HONEST GAP handed to the-oath: there is NO multi-step challenge
//  orchestration endpoint — kyc.runLiveness is a single passive+active check,
//  so the blink/turn/smile tracker reflects ONE real verdict and never
//  fabricates per-step passes. Proposed: kyc.submitLivenessChallenge
//  ({ sessionId, challenge, frameRef }) → { step, passed, nextChallenge }.
//  transportMode = truck · country US (FMCSA identity-proofing).
//
//  Persona: Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882 · DR-00427.
//

import SwiftUI

private struct LivenessOut: Decodable { let score: Double?; let livenessPassed: Bool? }
private struct VerifRow: Decodable { let id: Int?; let status: String?; let createdAt: String? }
private struct VerifList: Decodable { let verifications: [VerifRow]? }

@MainActor
private final class LivenessChallengeViewModel: ObservableObject {
    @Published var running = false
    @Published var result: LivenessOut?
    @Published var priorVerifications = 0

    private struct EmptyIn: Encodable {}
    private struct VerifIn: Encodable { let limit: Int }

    func loadHistory() async {
        let list: VerifList? = try? await EusoTripAPI.shared.query(
            "kyc.getVerifications", input: VerifIn(limit: 10))
        priorVerifications = list?.verifications?.count ?? 0
    }

    func run() async {
        guard !running else { return }
        running = true; defer { running = false }
        result = try? await EusoTripAPI.shared.mutation("kyc.runLiveness", input: EmptyIn())
        await loadHistory()
    }

    var passed: Bool { result?.livenessPassed == true }
    var reviewed: Bool { result != nil && result?.livenessPassed != true }
    var scorePct: Int? { result?.score.map { Int(($0 <= 1 ? $0 * 100 : $0).rounded()) } }
}

struct DriverLivenessChallengeView: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm = LivenessChallengeViewModel()
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DriverComplianceHeader(
                eyebrow: "DRIVER · IDENTITY · LIVENESS", caption: "MOTUS IDV",
                title: "Liveness check", subtitle: "Active anti-spoof challenge",
                rightLabel: "STATE", rightValue: stateLabel)
            IridescentHairline().padding(.top, Space.s3)
            content
        }
        .task { await vm.loadHistory() }
    }

    private var content: some View {
        VStack(spacing: Space.s4) {
            cameraHero
            stepTracker
            telemetry
            if vm.priorVerifications > 0 { historyNote }
            ctaPair
        }
        .padding(Space.s5)
    }

    // Dominant full-frame camera challenge viewport.
    private var cameraHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Color(hex: 0x0E1218))
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Brand.blue.opacity(0.07))
            FaceOval().stroke(LinearGradient.primary, lineWidth: 3)
                .frame(width: 148, height: 184)
                .scaleEffect(reduceMotion ? 1 : (pulse ? 1.03 : 1.0))
            // Turn-head cue arrow.
            Image(systemName: "arrow.right")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(LinearGradient.primary)
                .offset(x: 108)
            VStack {
                HStack(spacing: 5) {
                    Circle().fill(Brand.danger).frame(width: 8, height: 8)
                    Text(recLabel).font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                        .foregroundStyle(.white)
                    Spacer()
                }
                Spacer()
                Text(promptLabel).font(.system(size: 12, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.black.opacity(0.55), in: Capsule())
                Spacer()
                lockBar
            }
            .padding(Space.s4)
        }
        .frame(height: 288)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var lockBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(LinearGradient.primary)
                        .frame(width: geo.size.width * lockFraction)
                }
            }
            .frame(height: 12)
            HStack {
                Spacer()
                Text("\(Int(lockFraction * 100))% LOCK")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
            }
        }
    }

    private var lockFraction: CGFloat {
        if vm.passed { return 1 }
        if vm.running { return 0.66 }
        if vm.reviewed { return 0.4 }
        return 0.0
    }

    private var stepTracker: some View {
        HStack(spacing: 0) {
            challengeNode("Blink", done: vm.passed, active: vm.running, first: true)
            challengeConnector(done: vm.passed)
            challengeNode("Turn R", done: vm.passed, active: vm.running)
            challengeConnector(done: vm.passed)
            challengeNode("Smile", done: vm.passed, last: true)
        }
        .padding(.horizontal, Space.s2)
    }

    private func challengeNode(_ label: String, done: Bool, active: Bool = false,
                               first: Bool = false, last: Bool = false) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done ? AnyShapeStyle(LinearGradient.diagonal)
                          : AnyShapeStyle(active ? Brand.blue.opacity(0.18) : palette.bgCardSoft))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(done || active ? LinearGradient.diagonal
                                                   : LinearGradient(colors: [palette.borderSoft, palette.borderSoft],
                                                                    startPoint: .top, endPoint: .bottom),
                                                   lineWidth: 2))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else if active {
                    Circle().fill(LinearGradient.diagonal).frame(width: 8, height: 8)
                }
            }
            Text(label.uppercased()).font(.system(size: 10, weight: .bold))
                .foregroundStyle(done || active ? palette.textPrimary : palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    private func challengeConnector(done: Bool) -> some View {
        Rectangle().fill(done ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint))
            .frame(height: 2).offset(y: -9)
    }

    private var telemetry: some View {
        ComplianceSection(label: "ANTI-SPOOF TELEMETRY · MOTUS",
                          trailing: vm.passed ? "0 FLAGS" : (vm.reviewed ? "REVIEW" : "PENDING"),
                          trailingColor: vm.passed ? Brand.success : (vm.reviewed ? Brand.danger : Brand.warning)) {
            VStack(spacing: Space.s3) {
                telemetryRow("Depth map · 3D geometry", ok: vm.passed)
                Divider().overlay(palette.borderFaint)
                telemetryRow("Texture / moiré screen-replay", ok: vm.passed)
                Divider().overlay(palette.borderFaint)
                telemetryRow("Eye-blink micro-motion", ok: vm.passed)
                Text(vm.result == nil
                     ? "kyc.runLiveness · passive + active checks run on confirm"
                     : "kyc.runLiveness · verdict recorded to the identity-proofing log")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func telemetryRow(_ title: String, ok: Bool) -> some View {
        HStack(spacing: Space.s2) {
            Circle().fill(ok ? Brand.success : palette.textTertiary).frame(width: 8, height: 8)
            Text(title).font(EType.body).foregroundStyle(palette.textPrimary)
            Spacer()
            Text(ok ? "OK" : (vm.reviewed ? "CHECK" : "—"))
                .font(EType.micro).tracking(0.5).fontWeight(.bold)
                .foregroundStyle(ok ? Brand.success : palette.textTertiary)
        }
    }

    private var historyNote: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
            Text("\(vm.priorVerifications) prior identity verification\(vm.priorVerifications == 1 ? "" : "s") on record for you.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: vm.passed ? "Identity confirmed" : "Confirm identity",
                      action: { Task { await vm.run() } },
                      leadingIcon: vm.passed ? "checkmark.seal.fill" : "faceid",
                      isLoading: vm.running)
                .disabled(vm.passed)
            Button { dismiss() } label: {
                Text("Cancel").font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 140, minHeight: 52)
                    .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: labels
    private var stateLabel: String {
        if vm.passed { return "passed" }
        if vm.running { return "running" }
        if vm.reviewed { return "review" }
        return "ready"
    }
    private var recLabel: String {
        if vm.running { return "REC · MOTUS" }
        if vm.result != nil { return "DONE · MOTUS" }
        return "READY · MOTUS"
    }
    private var promptLabel: String {
        if vm.passed { return "IDENTITY CONFIRMED" }
        if vm.running { return "HOLD STILL…" }
        if vm.reviewed { return "RE-RUN NEEDED" }
        return "TAP CONFIRM TO START"
    }
}

// Rounded face-oval outline with eye dots + smile for the challenge viewport.
private struct FaceOval: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: rect)
        let eyeY = rect.minY + rect.height * 0.36
        p.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.30 - 4, y: eyeY, width: 8, height: 8))
        p.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.70 - 4, y: eyeY, width: 8, height: 8))
        let mY = rect.minY + rect.height * 0.64
        p.move(to: CGPoint(x: rect.midX - 20, y: mY))
        p.addQuadCurve(to: CGPoint(x: rect.midX + 20, y: mY),
                       control: CGPoint(x: rect.midX, y: mY + 14))
        return p
    }
}

// MARK: - Screen (Shell + Driver nav · TRIPS current)

struct DriverLivenessChallengeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DriverLivenessChallengeView()
        } nav: {
            BottomNav(leading: driverComplianceNavLeading(.trips),
                      trailing: driverComplianceNavTrailing(.trips), orbState: .listening)
        }
    }
}

#Preview("Liveness Challenge · Dark") {
    DriverLivenessChallengeScreen(theme: Theme.dark)
        .preferredColorScheme(.dark).environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}
#Preview("Liveness Challenge · Light") {
    DriverLivenessChallengeScreen(theme: Theme.light)
        .preferredColorScheme(.light).environment(\.palette, Theme.light)
        .background(Theme.light.bgPage)
}
