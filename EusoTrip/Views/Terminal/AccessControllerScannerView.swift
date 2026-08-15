//
//  AccessControllerScannerView.swift
//  EusoTrip — Terminal · Access control · scan (access-controller side).
//
//  The flip side of the staff ACCESS CARD: an access controller (gate guard,
//  yard supervisor, temporary access-card scanner) scans a staff member's
//  access-card QR OR types the 6-digit code, and the screen VERIFIES it
//  against the real `staffAccessTokens` grant via the server
//  `terminals.verifyStaffAccess` proc (being built on top of that grant — the
//  same tokens the existing `POST /validate/:token` route already validates).
//
//  HONESTY DOCTRINE — the whole point of this surface:
//   • The server is the ONLY arbiter of validity. The client renders the
//     answer verbatim; it NEVER fabricates a green "valid".
//   • `StaffAccessVerification.valid` defaults to FALSE on any decode miss, so
//     a malformed response can never read as a pass.
//   • A network failure is shown as an explicit "couldn't verify" state, NOT
//     a deny and NOT a pass — the controller is told to retry, never lied to.
//   • Expired / revoked / unknown are surfaced as DENY with the server's
//     reason verbatim.
//
//  CAMERA: reuses VisionKit's DataScannerViewController (the same engine
//  VINScannerSheet uses) for the QR. Where the camera isn't available the
//  surface degrades to the honest 6-digit code-entry field — never a dead end.
//
//  Reached from 700_TerminalHome ("Access control · scan") and 703_TerminalMe
//  (Operations → "Access control · scan"). Registered in ContentView as
//  "TerminalAccessScan" (role: .terminal).
//
//  Powered by ESANG AI™.
//

import SwiftUI
import VisionKit
import AVFoundation

// MARK: - Verification outcome (honest tri-state + in-flight + retry seam)

private enum AccessVerifyState: Equatable {
    case idle
    case verifying
    case valid(EusoTripAPI.StaffAccessVerification)
    case denied(EusoTripAPI.StaffAccessVerification)
    /// Network / server failure — NOT a deny. The controller is told to retry.
    case failed(String)
}

struct AccessControllerScannerView: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    @State private var state: AccessVerifyState = .idle
    @State private var manualCode: String = ""
    /// Guards against the camera firing the same payload repeatedly.
    @State private var lastScanned: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                scannerCard
                manualEntryCard
                resultCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                EusoTripEyebrow(verbatim: "TERMINAL · ACCESS CONTROL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: Space.s2)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(LinearGradient.diagonal.opacity(0.12)))
                    .overlay(Circle().strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Verify staff access")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(2).minimumScaleFactor(0.7)
                    Text("Scan an access card QR or enter the 6-digit code")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Scanner card (camera)

    @ViewBuilder
    private var scannerCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionLabel(icon: "camera.viewfinder", title: "SCAN QR")
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                AccessQRScannerHostView { payload in
                    // Debounce repeated emissions of the same payload.
                    guard payload != lastScanned else { return }
                    lastScanned = payload
                    Task { await verify(token: payload, code: nil) }
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .overlay(scanReticle)
            } else {
                // Honest "scanner coming" note for devices without the camera
                // scanner — the controller still has the code-entry path below.
                cameraUnavailableNote
            }
        }
    }

    private var scanReticle: some View {
        VStack {
            Spacer()
            Text("Aim at the staff access-card QR")
                .font(EType.caption).foregroundStyle(.white.opacity(0.9))
                .padding(.vertical, 10).frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.5))
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .allowsHitTesting(false)
    }

    private var cameraUnavailableNote: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Camera scanning isn't available on this device")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("Enter the staff member's 6-digit access code below — it verifies the same grant.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Manual code entry

    private var manualEntryCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionLabel(icon: "number", title: "OR ENTER 6-DIGIT CODE")
            HStack(spacing: 8) {
                TextField("000000", text: $manualCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .tracking(6)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onChange(of: manualCode) { _, newValue in
                        // Numeric-only, capped at 6.
                        let digits = String(newValue.filter(\.isNumber).prefix(6))
                        if digits != newValue { manualCode = digits }
                    }
                Button {
                    Task { await verify(token: nil, code: manualCode) }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(isCodeComplete ? AnyShapeStyle(LinearGradient.diagonal)
                                                         : AnyShapeStyle(palette.textTertiary))
                }
                .buttonStyle(.plain)
                .disabled(!isCodeComplete || state == .verifying)
            }
        }
    }

    private var isCodeComplete: Bool { manualCode.filter(\.isNumber).count == 6 }

    // MARK: - Result (honest tri-state)

    @ViewBuilder
    private var resultCard: some View {
        switch state {
        case .idle:
            EmptyView()
        case .verifying:
            HStack(spacing: 10) {
                ProgressView().tint(palette.textPrimary)
                Text("Verifying with the terminal…")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Spacer()
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        case .valid(let v):
            verdictCard(
                color: Brand.success, icon: "checkmark.seal.fill", title: "ACCESS GRANTED",
                v: v, fallbackReason: "Valid temporary access.")
        case .denied(let v):
            verdictCard(
                color: Brand.danger, icon: "xmark.seal.fill", title: "ACCESS DENIED",
                v: v, fallbackReason: "This access card is expired, revoked, or not recognized.")
        case .failed(let msg):
            // NOT a deny — an honest "couldn't verify" with retry.
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Couldn't verify").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(msg).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(3)
                    Text("This is a connection problem, not a denial. Try again.")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                Button("Reset") { resetScan() }
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.warning.opacity(0.5), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func verdictCard(color: Color, icon: String, title: String,
                             v: EusoTripAPI.StaffAccessVerification,
                             fallbackReason: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 18, weight: .heavy)).foregroundStyle(color)
                Text(title).font(.system(size: 14, weight: .heavy)).tracking(0.8).foregroundStyle(color)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                if let n = v.staffName, !n.isEmpty { kv("STAFF", n) }
                if let r = v.role, !r.isEmpty { kv("ROLE", r) }
                if let e = v.expiresAt, !e.isEmpty { kv("EXPIRES", e) }
                kv("RESULT", v.reason?.isEmpty == false ? v.reason! : fallbackReason)
            }
            Button { resetScan() } label: {
                Text("Scan another")
                    .font(.system(size: 13, weight: .heavy))
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.55), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 84, alignment: .leading)
            Text(v).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func sectionLabel(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(LinearGradient.diagonal)
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textPrimary)
            Spacer()
        }
    }

    // MARK: - Behavior

    private func resetScan() {
        state = .idle
        manualCode = ""
        lastScanned = nil
    }

    @MainActor
    private func verify(token: String?, code: String?) async {
        state = .verifying
        do {
            let result = try await EusoTripAPI.shared.verifyStaffAccess(token: token, code: code)
            // The server is the sole arbiter — render its answer verbatim.
            state = result.valid ? .valid(result) : .denied(result)
        } catch {
            state = .failed(accessCheckFailureCopy(error))
        }
    }
}

// MARK: - Registered host (ScreenRegistry, role:.terminal)
//
// Wraps the scanner in the canonical `Shell` with the Terminal bottom bar so it
// slots into the registry like 700/701/702/703. Reached by id
// "TerminalAccessScan" via `.eusoTerminalNavSwap` — a horizontal push (it's not
// a tabRoot), with the back chrome supplied by `TerminalSurface`.

struct TerminalAccessScanScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            AccessControllerScannerView()
        } nav: {
            BottomNav(
                leading: TerminalNavRoute.leading(current: .movements),
                trailing: TerminalNavRoute.trailing(current: .movements),
                orbState: .idle
            )
        }
    }
}

// MARK: - DataScannerViewController wrapper (QR only)
//
// Mirrors VINScannerSheet's DataScannerHostView, narrowed to QR symbology for
// the access card. Fires the FIRST QR payload it sees, then stops scanning so a
// single card isn't verified repeatedly.

private struct AccessQRScannerHostView: UIViewControllerRepresentable {
    let onPayload: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        guard DataScannerViewController.isSupported,
              DataScannerViewController.isAvailable else {
            return UIViewController()
        }
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        DispatchQueue.main.async { try? scanner.startScanning() }
        return scanner
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coord { Coord(onPayload: onPayload) }

    final class Coord: NSObject, DataScannerViewControllerDelegate {
        let onPayload: (String) -> Void
        private var fired = false
        init(onPayload: @escaping (String) -> Void) { self.onPayload = onPayload }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle(item, scanner: dataScanner)
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems where handle(item, scanner: dataScanner) { return }
        }

        @discardableResult
        private func handle(_ item: RecognizedItem, scanner: DataScannerViewController) -> Bool {
            guard !fired else { return false }
            if case .barcode(let b) = item, let payload = b.payloadStringValue, !payload.isEmpty {
                fired = true
                scanner.stopScanning()
                onPayload(payload)
                return true
            }
            return false
        }
    }
}

// MARK: - Previews

#Preview("Access Controller Scanner · Dark") {
    AccessControllerScannerView()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("Access Controller Scanner · Light") {
    AccessControllerScannerView()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}

// MARK: - Operator-facing failure copy

/// Operator-language reason an access check couldn't be completed.
///
/// A failure here is never a denial — the gate operator must be able to
/// tell "I couldn't check" from "this card is bad", so no branch reads as
/// a verdict. The caught error stays available for logging; the operator
/// never sees a raw `NSError` description.
fileprivate func accessCheckFailureCopy(_ error: Error) -> String {
    if let api = error as? EusoTripAPIError {
        switch api {
        case .unauthenticated:
            return "Your gate session expired, so the card wasn't checked. Sign in again and rescan."
        case .forbidden(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "This gate account isn't cleared to check access cards. The card wasn't checked."
                : trimmed
        case .trpcError(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "The check was rejected before it ran. Rescan the card."
                : trimmed
        case .httpStatus(let code, _):
            return "The check didn't complete (code \(code)). The card wasn't checked — rescan it."
        case .decodingFailed:
            return "The answer came back in a form this build can't read, so the card wasn't checked. Update the app, then rescan."
        case .empty:
            return "No answer came back, so the card wasn't checked. Rescan it."
        case .notConfigured, .badURL:
            return "This scanner isn't set up for live access checks yet. Restart the app and rescan."
        case .queuedForOfflineReplay:
            return "You're offline, so the card wasn't checked. Rescan once you reconnect."
        }
    }
    if (error as NSError).domain == NSURLErrorDomain {
        return "No connection, so the card wasn't checked. Rescan once you have signal."
    }
    return "The card wasn't checked. Rescan it."
}
