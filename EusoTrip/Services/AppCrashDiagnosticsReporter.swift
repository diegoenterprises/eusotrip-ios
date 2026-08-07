//
//  AppCrashDiagnosticsReporter.swift
//  EusoTrip
//
//  Sends iOS crash diagnostics through the authenticated backend audit trail.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MetricKit)
import MetricKit
#endif

final class AppCrashDiagnosticsReporter: NSObject {
    static let shared = AppCrashDiagnosticsReporter()

    private let pendingKey = "euso.mobileDiagnostics.pending"
    private let surfaceKey = "euso.mobileDiagnostics.lastSurface"
    private let sessionKey = "euso.mobileDiagnostics.sessionId"
    private let maxPayloadCharacters = 240_000
    private let maxPendingReports = 12
    @MainActor private var started = false

    private override init() {
        super.init()
    }

    @MainActor
    func start() {
        guard !started else { return }
        started = true
        recordSurface("app.boot")
        #if canImport(MetricKit)
        MXMetricManager.shared.add(self)
        #endif
        Task { @MainActor in
            await flushPendingReports()
        }
    }

    @MainActor
    func flushAfterAuthentication() async {
        await flushPendingReports()
    }

    @MainActor
    func recordSurface(_ surface: String) {
        let cleaned = surface
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(160)
        guard !cleaned.isEmpty else { return }
        UserDefaults.standard.set(String(cleaned), forKey: surfaceKey)
    }

    @MainActor
    private func submitDiagnostic(payloadJSON: String, source: String, occurredAt: Date = Date()) async {
        let input = DiagnosticReportInput(
            source: source,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            bundleId: Bundle.main.bundleIdentifier,
            osVersion: Self.osVersion,
            deviceModel: Self.deviceModel,
            routeHint: UserDefaults.standard.string(forKey: surfaceKey),
            sessionId: sessionId(),
            occurredAt: ISO8601DateFormatter().string(from: occurredAt),
            payloadJSON: String(payloadJSON.prefix(maxPayloadCharacters))
        )

        if !(await send(input)) {
            enqueue(input)
        }
    }

    @MainActor
    private func flushPendingReports() async {
        let pending = loadPendingReports()
        guard !pending.isEmpty else { return }

        var survivors: [DiagnosticReportInput] = []
        for report in pending {
            if !(await send(report)) {
                survivors.append(report)
            }
        }
        savePendingReports(survivors)
    }

    @MainActor
    private func send(_ input: DiagnosticReportInput) async -> Bool {
        struct Output: Decodable { let success: Bool }
        do {
            let out: Output = try await EusoTripAPI.shared.mutation(
                "mobileDiagnostics.report",
                input: input
            )
            return out.success
        } catch {
            return false
        }
    }

    private func enqueue(_ input: DiagnosticReportInput) {
        var pending = loadPendingReports()
        pending.append(input)
        if pending.count > maxPendingReports {
            pending = Array(pending.suffix(maxPendingReports))
        }
        savePendingReports(pending)
    }

    private func loadPendingReports() -> [DiagnosticReportInput] {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let reports = try? JSONDecoder().decode([DiagnosticReportInput].self, from: data)
        else { return [] }
        return reports
    }

    private func savePendingReports(_ reports: [DiagnosticReportInput]) {
        if reports.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingKey)
            return
        }
        guard let data = try? JSONEncoder().encode(reports) else { return }
        UserDefaults.standard.set(data, forKey: pendingKey)
    }

    private func sessionId() -> String {
        if let existing = UserDefaults.standard.string(forKey: sessionKey), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: sessionKey)
        return fresh
    }

    private static var osVersion: String {
        #if canImport(UIKit)
        return "iOS \(UIDevice.current.systemVersion)"
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private static var deviceModel: String {
        #if canImport(UIKit)
        return UIDevice.current.model
        #else
        return "Apple"
        #endif
    }
}

#if canImport(MetricKit)
extension AppCrashDiagnosticsReporter: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let data = payload.jsonRepresentation()
            let json = String(data: data, encoding: .utf8) ?? "{}"
            Task { @MainActor in
                await self.submitDiagnostic(payloadJSON: json, source: "ios-metrickit")
            }
        }
    }
}
#endif

private struct DiagnosticReportInput: Codable {
    let source: String
    let appVersion: String?
    let buildNumber: String?
    let bundleId: String?
    let osVersion: String?
    let deviceModel: String?
    let routeHint: String?
    let sessionId: String
    let occurredAt: String
    let payloadJSON: String
}
