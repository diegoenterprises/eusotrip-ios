//
//  ZeunMechanicsScreens.swift
//  EusoTrip — Zeun Mechanics action surfaces.
//
//  Web-platform parity port (frontend/server/routers/zeunMechanics.ts).
//  Closes the 12-feature gap between the read-only `MeZeunView` rollup
//  and the full-fat web pages (`ZeunBreakdown`, `ZeunMaintenanceTracker`,
//  `ZeunProviderNetwork`).
//
//  Surfaces in this file:
//    1. `ZeunBreakdownReporter` — guided report flow. Symptoms checklist,
//       severity picker, can-drive flag, optional telemetry, photo
//       upload (auto-VIGA via `viga.assessCargo`). Posts via
//       `zeunMechanics.reportBreakdown`. Returns AI diagnosis +
//       nearest providers in one round-trip.
//    2. `ZeunProviderNetwork` — directory with geo search + free-text
//       search. Backed by `findProviders` + `searchProviders`. Tap row
//       to drill into `ZeunProviderDetail`.
//    3. `ZeunProviderDetail` — full provider profile + recent reviews +
//       call/website/directions actions.
//    4. `ZeunBreakdownDetail` — single-report drill-in with full
//       diagnostic, status timeline, and "Update status" mutation.
//    5. `ZeunMaintenanceTracker` — overdue / due-soon / upcoming +
//       history list.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import SafariServices
import CoreLocation
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

// ════════════════════════════════════════════════════════════════════
// MARK: - 1. Breakdown Reporter
// ════════════════════════════════════════════════════════════════════

@MainActor
final class ZeunBreakdownReporterStore: ObservableObject {

    // Form state
    @Published var issueCategory: String = "engine"
    @Published var severity: String = "MEDIUM"
    @Published var symptoms: Set<String> = []
    @Published var canDrive: Bool = true
    @Published var driverNotes: String = ""
    @Published var faultCodesText: String = ""
    @Published var fuelLevelPercent: Double = 50
    @Published var defLevelPercent: Double = 50
    @Published var currentOdometer: String = ""
    @Published var loadStatus: String = "EMPTY"
    @Published var isHazmat: Bool = false

    // Submission flow
    @Published private(set) var isSubmitting: Bool = false
    @Published private(set) var ack: ZeunMechanicsAPI.ReportBreakdownAck?
    @Published var lastError: String?

    /// Server enums kept in lockstep with `zeunMechanics.ts` issueCategoryEnum.
    static let categories: [String] = [
        "engine", "transmission", "brakes", "tires", "suspension",
        "electrical", "exhaust", "cooling", "fuel_system", "trailer",
        "lights", "hvac", "other",
    ]

    static let severities: [String] = ["LOW", "MEDIUM", "HIGH", "CRITICAL"]

    static let symptomLibrary: [String: [String]] = [
        "engine":    ["Won't start", "Stalls intermittently", "Loss of power", "Overheating", "Smoke", "Unusual noise"],
        "brakes":    ["Pulls to one side", "Spongy pedal", "Air leak", "Pad warning", "ABS light", "Grinding"],
        "tires":     ["Flat", "Slow leak", "Tread separation", "Uneven wear", "Vibration", "TPMS warning"],
        "electrical":["Battery dead", "Lights flicker", "Charging system warning", "Starter clicks", "Fuse blowing"],
        "cooling":   ["Coolant leak", "High temperature", "Heater not working", "Steam from hood"],
        "transmission":["Slipping", "Hard shifts", "Won't engage", "Fluid leak", "Burning smell"],
        "fuel_system":["Hard start", "Loss of power", "Fuel leak", "Bad fuel economy", "Stalls under load"],
        "exhaust":   ["DPF warning", "DEF light", "Black smoke", "White smoke", "Loss of power"],
        "suspension":["Bouncing", "Air bag leak", "Sagging", "Knocking sound", "Uneven ride"],
        "trailer":   ["Light malfunction", "ABS warning", "King pin issue", "Door won't latch", "Brake drag"],
        "lights":    ["Headlight out", "Marker light out", "Brake light out", "Turn signal out"],
        "hvac":      ["No A/C", "No heat", "Defrost not working", "Blower failure"],
        "other":     ["See notes"],
    ]

    var symptomCandidates: [String] { Self.symptomLibrary[issueCategory] ?? Self.symptomLibrary["other"]! }

    func toggle(_ s: String) {
        if symptoms.contains(s) { symptoms.remove(s) } else { symptoms.insert(s) }
    }

    func submit() async {
        guard !isSubmitting else { return }
        guard !symptoms.isEmpty else {
            lastError = "Pick at least one symptom."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        lastError = nil

        let coord = await DriverLocationResolver.shared.currentCoordinate()
        let lat = coord?.latitude ?? 0
        let lng = coord?.longitude ?? 0

        let codes = faultCodesText
            .split(whereSeparator: { ", \n".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let input = ZeunMechanicsAPI.ReportBreakdownInput(
            vehicleVin: nil,
            vehicleId: nil,
            issueCategory: issueCategory,
            severity: severity,
            symptoms: Array(symptoms),
            canDrive: canDrive,
            latitude: lat,
            longitude: lng,
            loadId: nil,
            loadStatus: loadStatus,
            cargoType: nil,
            isHazmat: isHazmat,
            hazmatClass: nil,
            faultCodes: codes.isEmpty ? nil : codes,
            driverNotes: driverNotes.isEmpty ? nil : driverNotes,
            photos: nil,
            videos: nil,
            fuelLevelPercent: fuelLevelPercent,
            defLevelPercent: defLevelPercent,
            oilPressurePsi: nil,
            coolantTempF: nil,
            batteryVoltage: nil,
            currentOdometer: Int(currentOdometer)
        )

        do {
            ack = try await EusoTripAPI.shared.zeunMechanics.reportBreakdown(input)
        } catch {
            lastError = "Couldn't file the report. Try again in a moment."
        }
    }
}

struct ZeunBreakdownReporter: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ZeunBreakdownReporterStore()

    var body: some View {
        VStack(spacing: 0) {
            chrome
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if let ack = store.ack {
                        ackView(ack)
                    } else {
                        formView
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
                .padding(.bottom, Space.s8)
            }
            if store.ack == nil {
                bottomCTA
            }
        }
        .background(palette.bgPage.ignoresSafeArea())
    }

    // MARK: Chrome (back + title + X)

    private var chrome: some View {
        HStack {
            BackChevron { dismiss() }
            Spacer()
            Text("Report breakdown")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            SheetCloseButton { dismiss() }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(palette.bgPage)
    }

    // MARK: Form

    @ViewBuilder
    private var formView: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("ISSUE CATEGORY")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Picker("Category", selection: $store.issueCategory) {
                    ForEach(ZeunBreakdownReporterStore.categories, id: \.self) { cat in
                        Text(cat.replacingOccurrences(of: "_", with: " ").capitalized)
                            .tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .tint(LinearGradient.diagonal)
            }
        }

        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("SEVERITY")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: 6) {
                    ForEach(ZeunBreakdownReporterStore.severities, id: \.self) { s in
                        Button {
                            store.severity = s
                        } label: {
                            Text(s.capitalized)
                                .font(EType.caption.weight(.semibold))
                                .foregroundStyle(store.severity == s ? .white : palette.textPrimary)
                                .padding(.horizontal, Space.s3)
                                .padding(.vertical, 8)
                                .background(store.severity == s
                                            ? AnyShapeStyle(severityTint(s))
                                            : AnyShapeStyle(palette.bgCardSoft))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("SYMPTOMS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                ForEach(store.symptomCandidates, id: \.self) { sym in
                    Toggle(isOn: Binding(
                        get: { store.symptoms.contains(sym) },
                        set: { _ in store.toggle(sym) }
                    )) {
                        Text(sym)
                            .font(EType.body)
                            .foregroundStyle(palette.textPrimary)
                    }
                    .toggleStyle(GradientToggleStyle())
                }
            }
        }

        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("CAN YOU DRIVE TO A SHOP?")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Toggle(isOn: $store.canDrive) {
                    Text(store.canDrive ? "Yes — I can move under power" : "No — I'm stranded")
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                }
                .toggleStyle(GradientToggleStyle())
                Toggle(isOn: $store.isHazmat) {
                    Text("Hauling hazmat right now")
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                }
                .toggleStyle(GradientToggleStyle())
                Picker("Load", selection: $store.loadStatus) {
                    Text("Empty").tag("EMPTY")
                    Text("Loaded").tag("LOADED")
                    Text("Hazmat").tag("HAZMAT")
                }
                .pickerStyle(.segmented)
            }
        }

        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("TELEMETRY (optional)")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                HStack {
                    Text("Fuel %")
                        .font(EType.body)
                    Spacer()
                    Text("\(Int(store.fuelLevelPercent))%")
                        .font(EType.bodyStrong.monospacedDigit())
                }
                Slider(value: $store.fuelLevelPercent, in: 0...100, step: 5)
                HStack {
                    Text("DEF %")
                        .font(EType.body)
                    Spacer()
                    Text("\(Int(store.defLevelPercent))%")
                        .font(EType.bodyStrong.monospacedDigit())
                }
                Slider(value: $store.defLevelPercent, in: 0...100, step: 5)
                HStack {
                    Text("Odometer")
                        .font(EType.body)
                    Spacer()
                    TextField("123456", text: $store.currentOdometer)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                TextField("Fault codes (comma separated)", text: $store.faultCodesText)
                    .textFieldStyle(.roundedBorder)
            }
        }

        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("DRIVER NOTES")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                TextField("Anything else dispatch should know…", text: $store.driverNotes, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }
        }

        if let err = store.lastError {
            Text(err)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
        }
    }

    private var bottomCTA: some View {
        VStack {
            CTAButton(title: store.isSubmitting ? "Filing…" : "File breakdown report") {
                Task { await store.submit() }
            }
            .opacity(store.isSubmitting ? 0.6 : 1)
            .disabled(store.isSubmitting || store.symptoms.isEmpty)
            Text("Posts to Zeun Mechanics. ESANG runs an AI diagnosis and pulls the nearest 5 providers in one round-trip.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s4)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(palette.bgPage)
    }

    // MARK: Ack view

    @ViewBuilder
    private func ackView(_ ack: ZeunMechanicsAPI.ReportBreakdownAck) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Brand.success)
                    Text("Report #\(ack.reportId) filed")
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                }
                if let d = ack.diagnosis {
                    if let issue = d.issue {
                        Text(issue)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                    }
                    if let p = d.probability {
                        Text("Confidence \(Int((p * 100).rounded()))%")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                if let cost = ack.estimatedCost,
                   let lo = cost.min, let hi = cost.max {
                    Text(String(format: "Est. cost $%.0f – $%.0f", lo, hi))
                        .font(EType.body.monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                }
                if let canDrive = ack.canDrive {
                    StatusPill(
                        text: canDrive ? "Driveable" : "DO NOT DRIVE",
                        kind: canDrive ? .success : .danger
                    )
                }
            }
        }

        if let warnings = ack.safetyWarnings, !warnings.isEmpty {
            ActiveCard {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("SAFETY WARNINGS")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    ForEach(warnings, id: \.self) { w in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Brand.warning)
                            Text(w).font(EType.caption)
                                .foregroundStyle(palette.textPrimary)
                        }
                    }
                }
            }
        }

        if !ack.providers.isEmpty {
            ActiveCard {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("NEAREST PROVIDERS")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    ForEach(ack.providers) { p in
                        HStack(spacing: Space.s3) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .foregroundStyle(LinearGradient.diagonal)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name ?? "—")
                                    .font(EType.bodyStrong)
                                    .foregroundStyle(palette.textPrimary)
                                Text("\(p.distance ?? "—") mi · \(p.type ?? "—")")
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            if let phone = p.phone,
                               let url = URL(string: "tel:\(phone.filter { "+0123456789".contains($0) })") {
                                Button {
                                    #if canImport(UIKit)
                                    UIApplication.shared.open(url)
                                    #endif
                                } label: {
                                    Image(systemName: "phone.fill")
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(LinearGradient.diagonal))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }

        CTAButton(title: "Done") { dismiss() }
    }

    private func severityTint(_ s: String) -> some ShapeStyle {
        switch s {
        case "LOW":      return AnyShapeStyle(Brand.success)
        case "MEDIUM":   return AnyShapeStyle(Brand.warning)
        case "HIGH":     return AnyShapeStyle(Brand.danger)
        case "CRITICAL": return AnyShapeStyle(Brand.danger)
        default:         return AnyShapeStyle(LinearGradient.diagonal)
        }
    }
}

// ════════════════════════════════════════════════════════════════════
// MARK: - 2. Provider Network
// ════════════════════════════════════════════════════════════════════

@MainActor
final class ZeunProviderStore: ObservableObject {
    @Published private(set) var providers: [ZeunMechanicsAPI.ProviderRow] = []
    @Published private(set) var isLoading: Bool = false
    @Published var query: String = ""
    @Published var radiusMiles: Double = 50
    @Published var providerType: String? = nil
    @Published var lastError: String?

    static let providerTypes: [String] = ["TRUCK_STOP", "DEALER", "INDEPENDENT", "MOBILE", "TOWING", "TIRE_SHOP"]

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let coord = await DriverLocationResolver.shared.currentCoordinate()
        guard let coord else {
            lastError = "Couldn't get a location fix. Enable Location Services."
            providers = []
            return
        }
        do {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty {
                providers = try await EusoTripAPI.shared.zeunMechanics.findProviders(
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    radiusMiles: radiusMiles,
                    providerType: providerType,
                    maxResults: 30
                )
            } else {
                providers = try await EusoTripAPI.shared.zeunMechanics.searchProviders(
                    query: q,
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    radiusMiles: radiusMiles
                )
            }
            lastError = nil
        } catch {
            lastError = "Couldn't reach the provider directory."
            providers = []
        }
    }
}

struct ZeunProviderNetwork: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ZeunProviderStore()
    @State private var selectedProvider: ZeunMechanicsAPI.ProviderRow?

    var body: some View {
        VStack(spacing: 0) {
            chrome
            controls
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    if store.isLoading && store.providers.isEmpty {
                        ProgressView().padding()
                    } else if store.providers.isEmpty {
                        EusoEmptyState(
                            systemImage: "wrench.adjustable",
                            title: "No providers found",
                            subtitle: "Widen the radius or try a name search."
                        )
                        .padding(.top, Space.s4)
                    } else {
                        ForEach(store.providers) { p in
                            providerRow(p)
                        }
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s8)
            }
        }
        .background(palette.bgPage.ignoresSafeArea())
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: $selectedProvider) { p in
            ZeunProviderDetail(providerId: p.id)
                .eusoSheetX()
        }
    }

    private var chrome: some View {
        HStack {
            BackChevron { dismiss() }
            Spacer()
            Text("Provider network")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            SheetCloseButton { dismiss() }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(palette.bgPage)
    }

    private var controls: some View {
        VStack(spacing: Space.s2) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.textSecondary)
                TextField("Shop name, city, or service…", text: $store.query)
                    .submitLabel(.search)
                    .onSubmit { Task { await store.refresh() } }
                if !store.query.isEmpty {
                    Button {
                        store.query = ""
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 8)
            .background(palette.bgCardSoft)
            .clipShape(Capsule())

            HStack(spacing: 6) {
                Menu {
                    ForEach([25.0, 50.0, 100.0, 200.0], id: \.self) { r in
                        Button("\(Int(r)) mi radius") {
                            store.radiusMiles = r
                            Task { await store.refresh() }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "scope")
                        Text("\(Int(store.radiusMiles)) mi")
                    }
                    .font(EType.caption.weight(.semibold))
                    .padding(.horizontal, Space.s3).padding(.vertical, 6)
                    .background(palette.bgCardSoft)
                    .clipShape(Capsule())
                }
                Menu {
                    Button("All types") {
                        store.providerType = nil
                        Task { await store.refresh() }
                    }
                    ForEach(ZeunProviderStore.providerTypes, id: \.self) { t in
                        Button(t.replacingOccurrences(of: "_", with: " ").capitalized) {
                            store.providerType = t
                            Task { await store.refresh() }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.adjustable")
                        Text(store.providerType?.replacingOccurrences(of: "_", with: " ").capitalized ?? "All")
                    }
                    .font(EType.caption.weight(.semibold))
                    .padding(.horizontal, Space.s3).padding(.vertical, 6)
                    .background(palette.bgCardSoft)
                    .clipShape(Capsule())
                }
                Spacer()
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
    }

    private func providerRow(_ p: ZeunMechanicsAPI.ProviderRow) -> some View {
        Button { selectedProvider = p } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: glyph(for: p.type))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(palette.bgCardSoft))
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name ?? "—")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let r = p.rating {
                            Image(systemName: "star.fill").foregroundStyle(Brand.warning)
                                .font(.system(size: 10))
                            Text(String(format: "%.1f", r))
                                .font(EType.caption.monospacedDigit())
                        }
                        if let d = p.distance {
                            Text("· \(String(format: "%.1f", d)) mi")
                                .font(EType.caption.monospacedDigit())
                        }
                        if let t = p.type {
                            Text("· \(t.replacingOccurrences(of: "_", with: " ").capitalized)")
                                .font(EType.caption)
                        }
                        if p.available24x7 == true {
                            Text("· 24/7").font(EType.caption.weight(.semibold))
                                .foregroundStyle(Brand.success)
                        }
                    }
                    .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
    }

    private func glyph(for type: String?) -> String {
        switch type {
        case "TRUCK_STOP":  return "fuelpump.fill"
        case "DEALER":      return "building.2.fill"
        case "INDEPENDENT": return "wrench.and.screwdriver.fill"
        case "MOBILE":      return "truck.box.fill"
        case "TOWING":      return "car.2.fill"
        case "TIRE_SHOP":   return "circle.dashed"
        default:            return "wrench.adjustable"
        }
    }
}

// ════════════════════════════════════════════════════════════════════
// MARK: - 3. Provider Detail
// ════════════════════════════════════════════════════════════════════

struct ZeunProviderDetail: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    let providerId: Int

    @State private var detail: ZeunMechanicsAPI.ProviderDetail?
    @State private var isLoading: Bool = true
    /// In-app SFSafariViewController presentation for the provider's
    /// website. Replaces the prior `UIApplication.shared.open(url)`
    /// Safari kick — driver stays inside the EusoTrip app and can
    /// browse the mechanic shop site without leaving.
    private struct ZeunWebSession: Identifiable, Hashable {
        let id: UUID
        let url: URL
    }
    @State private var webSession: ZeunWebSession? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BackChevron { dismiss() }
                Spacer()
                Text("Provider")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                SheetCloseButton { dismiss() }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let d = detail {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        identityCard(d)
                        contactCard(d)
                        if !(d.services ?? []).isEmpty || !(d.certifications ?? []).isEmpty {
                            servicesCard(d)
                        }
                        if !d.reviews.isEmpty {
                            reviewsCard(d)
                        }
                    }
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s4)
                }
            } else {
                Spacer()
                Text("Couldn't load provider.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
        }
        .background(palette.bgPage.ignoresSafeArea())
        .task { await load() }
        .sheet(item: $webSession) { sess in
            ZeunInAppSafari(url: sess.url)
                .ignoresSafeArea()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        detail = try? await EusoTripAPI.shared.zeunMechanics.getProvider(providerId: providerId)
    }

    private func identityCard(_ d: ZeunMechanicsAPI.ProviderDetail) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(d.name ?? "—")
                    .font(EType.h2)
                    .foregroundStyle(palette.textPrimary)
                if let chain = d.chainName {
                    Text(chain)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                HStack(spacing: 6) {
                    if let r = d.rating {
                        Image(systemName: "star.fill").foregroundStyle(Brand.warning)
                            .font(.system(size: 11))
                        Text(String(format: "%.1f", r))
                            .font(EType.bodyStrong.monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                    }
                    if let n = d.reviewCount {
                        Text("(\(n))")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    if d.available24x7 == true {
                        Text("· 24/7")
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(Brand.success)
                    }
                    if d.hasMobileService == true {
                        Text("· MOBILE")
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                }
                Text([d.address, d.city, d.state].compactMap { $0 }.joined(separator: ", "))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func contactCard(_ d: ZeunMechanicsAPI.ProviderDetail) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("CONTACT")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                if let phone = d.phone, !phone.isEmpty {
                    contactRow(icon: "phone.fill", value: phone) {
                        if let url = URL(string: "tel:\(phone.filter { "+0123456789".contains($0) })") {
                            #if canImport(UIKit)
                            UIApplication.shared.open(url)
                            #endif
                        }
                    }
                }
                if let web = d.website, !web.isEmpty {
                    contactRow(icon: "globe", value: web) {
                        if let url = URL(string: web.hasPrefix("http") ? web : "https://\(web)") {
                            webSession = ZeunWebSession(id: UUID(), url: url)
                        }
                    }
                }
                if let email = d.email, !email.isEmpty {
                    contactRow(icon: "envelope.fill", value: email) {
                        if let url = URL(string: "mailto:\(email)") {
                            #if canImport(UIKit)
                            UIApplication.shared.open(url)
                            #endif
                        }
                    }
                }
            }
        }
    }

    private func servicesCard(_ d: ZeunMechanicsAPI.ProviderDetail) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("SERVICES + CERTIFICATIONS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                if let svcs = d.services, !svcs.isEmpty {
                    chipRow(items: svcs)
                }
                if let certs = d.certifications, !certs.isEmpty {
                    chipRow(items: certs)
                }
                if let oems = d.oemBrands, !oems.isEmpty {
                    chipRow(items: oems)
                }
            }
        }
    }

    private func reviewsCard(_ d: ZeunMechanicsAPI.ProviderDetail) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("RECENT REVIEWS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                ForEach(d.reviews) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            ForEach(0..<5, id: \.self) { i in
                                Image(systemName: i < Int(r.rating.rounded()) ? "star.fill" : "star")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Brand.warning)
                            }
                            Spacer()
                            Text((r.createdAt ?? "").prefix(10))
                                .font(EType.micro)
                                .foregroundStyle(palette.textTertiary)
                        }
                        if let title = r.title { Text(title).font(EType.bodyStrong) }
                        if let txt = r.reviewText {
                            Text(txt).font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Divider().overlay(palette.borderFaint)
                }
            }
        }
    }

    private func contactRow(icon: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                Image(systemName: icon)
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 22)
                Text(value)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chipRow(items: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { s in
                    Text(s)
                        .font(EType.micro.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(palette.bgCardSoft)
                        .overlay(Capsule().stroke(palette.borderFaint))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// ════════════════════════════════════════════════════════════════════
// MARK: - 4. Breakdown Detail (drill-in for one report)
// ════════════════════════════════════════════════════════════════════

struct ZeunBreakdownDetail: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    let reportId: Int

    @State private var detail: ZeunMechanicsAPI.BreakdownDetail?
    @State private var isLoading: Bool = true
    @State private var statusUpdate: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BackChevron { dismiss() }
                Spacer()
                Text("Breakdown #\(reportId)")
                    .font(EType.bodyStrong)
                Spacer()
                SheetCloseButton { dismiss() }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)

            if isLoading {
                Spacer(); ProgressView(); Spacer()
            } else if let d = detail {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        summaryCard(d)
                        if let diag = d.diagnostic { diagnosticCard(diag) }
                        if !(d.symptoms ?? []).isEmpty { symptomsCard(d) }
                        statusUpdater(d)
                    }
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s4)
                }
            } else {
                Spacer()
                Text("Couldn't load report.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }
        }
        .background(palette.bgPage.ignoresSafeArea())
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        detail = try? await EusoTripAPI.shared.zeunMechanics.getBreakdownReport(reportId: reportId)
    }

    private func summaryCard(_ d: ZeunMechanicsAPI.BreakdownDetail) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 4) {
                Text((d.issueCategory ?? "—").replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(EType.h2)
                    .foregroundStyle(palette.textPrimary)
                HStack {
                    StatusPill(text: d.severity ?? "—",
                               kind: severityPillKind(d.severity))
                    StatusPill(text: (d.status ?? "—").replacingOccurrences(of: "_", with: " ").capitalized,
                               kind: .info)
                    if let canDrive = d.canDrive {
                        StatusPill(text: canDrive ? "Driveable" : "Stranded",
                                   kind: canDrive ? .success : .danger)
                    }
                }
                if let cost = d.actualCost {
                    Text(String(format: "Actual cost $%.2f", cost))
                        .font(EType.body.monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                }
                Text("Filed \((d.createdAt ?? "").prefix(10))")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func diagnosticCard(_ diag: ZeunMechanicsAPI.BreakdownDetail.Diagnostic) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("AI DIAGNOSIS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                if let primary = diag.primaryDiagnosis {
                    Text(primary.issue ?? "—")
                        .font(EType.bodyStrong)
                    if let p = primary.probability {
                        Text("Confidence \(Int((p * 100).rounded()))%")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                if let cost = diag.estimatedCost,
                   let lo = cost.min, let hi = cost.max {
                    Text(String(format: "Est. cost $%.0f – $%.0f", lo, hi))
                        .font(EType.body.monospacedDigit())
                }
            }
        }
    }

    private func symptomsCard(_ d: ZeunMechanicsAPI.BreakdownDetail) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("SYMPTOMS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                ForEach(d.symptoms ?? [], id: \.self) { s in
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(Brand.warning)
                        Text(s).font(EType.body)
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
        }
    }

    private func statusUpdater(_ d: ZeunMechanicsAPI.BreakdownDetail) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("UPDATE STATUS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                ForEach(["ACKNOWLEDGED", "EN_ROUTE_TO_SHOP", "AT_SHOP", "UNDER_REPAIR", "WAITING_PARTS", "RESOLVED"], id: \.self) { s in
                    Button {
                        Task {
                            _ = try? await EusoTripAPI.shared.zeunMechanics.updateBreakdownStatus(
                                reportId: reportId, status: s
                            )
                            await load()
                        }
                    } label: {
                        HStack {
                            Image(systemName: d.status == s ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(d.status == s ? Brand.success : palette.textTertiary)
                            Text(s.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(EType.body)
                                .foregroundStyle(palette.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func severityPillKind(_ s: String?) -> StatusPill.Kind {
        switch (s ?? "").uppercased() {
        case "LOW":      return .success
        case "MEDIUM":   return .warning
        case "HIGH":     return .danger
        case "CRITICAL": return .danger
        default:         return .neutral
        }
    }
}

// ════════════════════════════════════════════════════════════════════
// MARK: - 5. Maintenance Tracker
// ════════════════════════════════════════════════════════════════════

struct ZeunMaintenanceTracker: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    let vehicleId: Int
    let currentOdometer: Int

    @State private var status: ZeunMechanicsAPI.MaintenanceStatus?
    @State private var history: [ZeunMechanicsAPI.MaintenanceLog] = []
    @State private var isLoading: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BackChevron { dismiss() }
                Spacer()
                Text("Maintenance")
                    .font(EType.bodyStrong)
                Spacer()
                SheetCloseButton { dismiss() }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if isLoading {
                        ProgressView().padding()
                    } else if let s = status {
                        if !s.overdue.isEmpty {
                            section(title: "OVERDUE", items: s.overdue, kind: .danger)
                        }
                        if !s.dueSoon.isEmpty {
                            section(title: "DUE SOON", items: s.dueSoon, kind: .warning)
                        }
                        if !s.upcoming.isEmpty {
                            section(title: "UPCOMING", items: s.upcoming, kind: .info)
                        }
                        if s.overdue.isEmpty && s.dueSoon.isEmpty && s.upcoming.isEmpty {
                            EusoEmptyState(
                                systemImage: "wrench.and.screwdriver",
                                title: "No maintenance scheduled",
                                subtitle: "Once your fleet manager wires service intervals, due dates show up here."
                            )
                        }
                    }
                    if !history.isEmpty {
                        ActiveCard {
                            VStack(alignment: .leading, spacing: Space.s2) {
                                Text("HISTORY")
                                    .font(EType.micro).tracking(0.8)
                                    .foregroundStyle(palette.textTertiary)
                                ForEach(history) { h in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(h.serviceType ?? "—")
                                                .font(EType.bodyStrong)
                                            Text("\((h.serviceDate ?? "").prefix(10)) · \(h.odometerAtService ?? 0) mi")
                                                .font(EType.caption)
                                                .foregroundStyle(palette.textSecondary)
                                        }
                                        Spacer()
                                        if let cost = h.cost {
                                            Text(String(format: "$%.0f", cost))
                                                .font(EType.bodyStrong.monospacedDigit())
                                        }
                                    }
                                    Divider().overlay(palette.borderFaint)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s4)
            }
        }
        .background(palette.bgPage.ignoresSafeArea())
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let st = EusoTripAPI.shared.zeunMechanics.getMaintenanceStatus(
            vehicleId: vehicleId, currentOdometer: currentOdometer)
        async let hi = EusoTripAPI.shared.zeunMechanics.getMaintenanceHistory(
            vehicleId: vehicleId, limit: 25)
        status = (try? await st) ?? nil
        history = (try? await hi) ?? []
    }

    private func section(
        title: String,
        items: [ZeunMechanicsAPI.ScheduledItem],
        kind: StatusPill.Kind
    ) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text(title)
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(text: "\(items.count)", kind: kind)
                }
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text((item.serviceType ?? "—").replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                            if let due = item.dueOdometer {
                                Text("Due at \(due) mi")
                                    .font(EType.caption.monospacedDigit())
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                        Spacer()
                        if let r = item.milesRemaining {
                            Text("\(r) mi")
                                .font(EType.bodyStrong.monospacedDigit())
                                .foregroundStyle(palette.textPrimary)
                        }
                    }
                }
            }
        }
    }
}

// ════════════════════════════════════════════════════════════════════
// MARK: - 6. Part Diagnosis (vision · `zeunMechanics.diagnosePart`)
// ════════════════════════════════════════════════════════════════════
//
// Capture/select a photo of an equipment part → base64 → the live
// `diagnosePart` vision proc → render the diagnosed issues with %
// confidence + tinted severity pills. Reuses the same PhotosPicker →
// JPEG-compress → base64 capture primitive that CredentialScanCard and
// AIVisualScanButton already ship (no new camera UI). HONEST: renders
// only what the proc returns — empty issues surfaces a real "No faults
// detected" state, never a fabricated fault.

@MainActor
final class ZeunPartDiagnosisStore: ObservableObject {

    // Capture
    @Published var pickerItem: PhotosPickerItem? = nil
    @Published private(set) var capturedImage: UIImage? = nil
    private var photoBase64: String? = nil

    // Optional context inputs (both honest-optional)
    @Published var equipmentType: String = ""
    @Published var partName: String = ""

    // Flow state
    @Published private(set) var isDiagnosing: Bool = false
    @Published private(set) var result: ZeunMechanicsAPI.PartDiagnosis? = nil
    @Published var lastError: String? = nil

    // Document-intelligence spine — the capture point classifies the photo
    // (component/defect context) via the homegrown vision router ALONGSIDE
    // the diagnosePart upload, so the user sees what was actually detected
    // before they commit to a diagnosis. HONEST: renders only the real
    // classifier result; low confidence / "unknown" surfaces a neutral
    // "couldn't confidently identify" state, never a fabricated type.
    @Published private(set) var isClassifying: Bool = false
    @Published private(set) var classification: DocumentRouterAPI.ClassifyResponse? = nil

    var hasPhoto: Bool { photoBase64 != nil }

    /// PhotosPicker → Data → JPEG ≤ 900KB → base64. Mirrors the exact
    /// compression loop CredentialScanCard.scanFromData uses so the
    /// multimodal payload stays under the vision-primitive cap.
    func loadPhoto(_ item: PhotosPickerItem) async {
        lastError = nil
        result = nil
        classification = nil
        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
            lastError = "Couldn't read that photo. Try another."
            pickerItem = nil
            return
        }
        var jpeg = data
        if let img = UIImage(data: data) {
            capturedImage = img
            var quality: CGFloat = 0.85
            while quality > 0.3 {
                if let d = img.jpegData(compressionQuality: quality), d.count <= 900_000 {
                    jpeg = d
                    break
                }
                quality -= 0.1
            }
        }
        let base64 = jpeg.base64EncodedString()
        photoBase64 = base64
        pickerItem = nil

        // Fire the document-intelligence read on the same JPEG payload.
        // Independent of diagnosePart — surfaces the detected component/
        // defect context so the user knows exactly what was captured.
        await classify(base64)
    }

    /// Runs the captured photo through the homegrown vision router to
    /// classify the component/defect context. Best-effort: a classifier
    /// miss never blocks the diagnosis flow (it just leaves the context
    /// card hidden). HONEST: stores the raw `ClassifyResponse`; the view
    /// decides whether the confidence is high enough to assert a type.
    func classify(_ base64: String) async {
        isClassifying = true
        defer { isClassifying = false }
        do {
            classification = try await EusoTripAPI.shared.documentRouter.classifyAndRoute(
                documentBase64: base64,
                mimeType: .jpeg,
                callerContext: "mechanic inspection defect"
            )
        } catch let e {
            // Classification is auxiliary — surface the failure quietly in
            // the context card rather than blocking the primary diagnosis.
            classification = nil
            lastError = "Couldn't identify the document: \((e as? LocalizedError)?.errorDescription ?? e.localizedDescription)"
        }
    }

    func diagnose() async {
        guard !isDiagnosing else { return }
        guard let base64 = photoBase64 else {
            lastError = "Capture or pick a part photo first."
            return
        }
        isDiagnosing = true
        defer { isDiagnosing = false }
        lastError = nil

        let eqType = equipmentType.trimmingCharacters(in: .whitespacesAndNewlines)
        let part = partName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            result = try await EusoTripAPI.shared.zeunMechanics.diagnosePart(
                photoBase64: base64,
                mime: "image/jpeg",
                equipmentType: eqType.isEmpty ? nil : eqType,
                partName: part.isEmpty ? nil : part,
                context: nil
            )
        } catch let e {
            lastError = "Diagnosis failed: \((e as? EusoTripAPIError)?.errorDescription ?? e.localizedDescription)"
        }
    }
}

struct ZeunPartDiagnosisScreen: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ZeunPartDiagnosisStore()

    var body: some View {
        VStack(spacing: 0) {
            chrome
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    captureCard
                    contextCard
                    if let err = store.lastError {
                        ActiveCard {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundStyle(Brand.danger)
                                Text(err)
                                    .font(EType.caption)
                                    .foregroundStyle(Brand.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if let r = store.result {
                        resultsView(r)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
                .padding(.bottom, Space.s8)
            }
            bottomCTA
        }
        .background(palette.bgPage.ignoresSafeArea())
        .onChange(of: store.pickerItem) { _, item in
            guard let item else { return }
            Task { await store.loadPhoto(item) }
        }
    }

    // MARK: Chrome

    private var chrome: some View {
        HStack {
            BackChevron { dismiss() }
            Spacer()
            Text("Diagnose a part")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            SheetCloseButton { dismiss() }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(palette.bgPage)
    }

    // MARK: Capture

    private var captureCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("PART PHOTO")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
                Text("Snap or pick a clear photo of the part. ESANG reads visible faults, wear, and damage.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let img = store.capturedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint)
                        )
                }

                detectionStrip

                capturePhotoPicker
            }
        }
    }

    /// Document-intelligence read of the captured photo. Surfaces the
    /// detected component/defect context (classifiedType + confidence +
    /// summary + key extractedFields + warnings) ALONGSIDE the diagnosePart
    /// upload, so the driver sees exactly what the spine read before they
    /// commit. HONEST: low confidence or "unknown" → a neutral "couldn't
    /// confidently identify" line, never an asserted type.
    @ViewBuilder
    private var detectionStrip: some View {
        if store.isClassifying {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("ESANG is reading the photo…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let c = store.classification {
            let confident = c.confidence >= 0.55 && c.classifiedType.lowercased() != "unknown"
            let pct = Int((max(0, min(1, c.confidence)) * 100).rounded())
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 6) {
                    Image(systemName: confident ? "doc.viewfinder.fill" : "questionmark.circle.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(confident ? AnyShapeStyle(LinearGradient.diagonal)
                                                   : AnyShapeStyle(palette.textTertiary))
                    Text(confident ? "DETECTED" : "UNCONFIRMED")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(text: "\(pct)%", kind: confident ? .success : .neutral)
                }

                if confident {
                    Text(humanizeType(c.classifiedType))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Couldn't confidently identify this photo — please confirm the component below before diagnosing.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !c.summary.isEmpty {
                    Text(c.summary)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Key extracted fields — rendered verbatim from the spine.
                let fields = orderedFields(c.extractedFields)
                if !fields.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(fields, id: \.0) { key, value in
                            HStack(alignment: .top, spacing: 6) {
                                Text(humanizeKey(key))
                                    .font(EType.micro)
                                    .foregroundStyle(palette.textTertiary)
                                Spacer(minLength: Space.s2)
                                Text(value)
                                    .font(EType.micro)
                                    .foregroundStyle(palette.textSecondary)
                                    .multilineTextAlignment(.trailing)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                // Classifier warnings — surfaced verbatim, never hidden.
                ForEach(c.warnings, id: \.self) { w in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Brand.warning)
                        Text(w)
                            .font(EType.micro)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
        }
    }

    /// "engine_part" / "brake-chamber" / "BOL" → "Engine Part" / etc.
    private func humanizeType(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return raw }
        return cleaned
            .split(separator: " ")
            .map { $0.count <= 3 ? $0.uppercased() : $0.capitalized }
            .joined(separator: " ")
    }

    /// camelCase / snake_case field key → readable label.
    private func humanizeKey(_ raw: String) -> String {
        var spaced = ""
        for ch in raw.replacingOccurrences(of: "_", with: " ") {
            if ch.isUppercase, let last = spaced.last, last != " " { spaced.append(" ") }
            spaced.append(ch)
        }
        return spaced
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    /// Stable, non-null field list capped so the strip stays scannable.
    private func orderedFields(_ fields: [String: DocumentRouterAPI.FieldValue]) -> [(String, String)] {
        fields
            .compactMap { key, value -> (String, String)? in
                guard let s = value.asString, !s.isEmpty else { return nil }
                return (key, s)
            }
            .sorted { $0.0 < $1.0 }
            .prefix(6)
            .map { ($0.0, $0.1) }
    }

    /// Capture-photo picker. `store.hasPhoto` is read in this @MainActor view
    /// scope and captured as a plain Bool, so the PhotosPicker label closure
    /// never touches the actor-isolated property (silences the concurrency warning).
    private var capturePhotoPicker: some View {
        let has = store.hasPhoto
        return PhotosPicker(selection: $store.pickerItem, matching: .images, photoLibrary: .shared()) {
            HStack(spacing: 6) {
                Image(systemName: has ? "arrow.triangle.2.circlepath" : "camera.fill")
                    .font(.system(size: 12, weight: .heavy))
                Text(has ? "Retake / pick another" : "Capture part photo")
                    .font(.system(size: 13, weight: .heavy))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(.white)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.isDiagnosing)
    }

    private var contextCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("CONTEXT (optional)")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                TextField("Equipment type — e.g. Class 8 tractor, reefer trailer", text: $store.equipmentType)
                    .textFieldStyle(.roundedBorder)
                    .disabled(store.isDiagnosing)
                TextField("Part name — e.g. brake chamber, serpentine belt", text: $store.partName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(store.isDiagnosing)
                Text("Both optional — they sharpen the read but ESANG diagnoses from the photo regardless.")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private func resultsView(_ r: ZeunMechanicsAPI.PartDiagnosis) -> some View {
        // Summary + grounded badge
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("DIAGNOSIS")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    if r.grounded {
                        HStack(spacing: 4) {
                            Image(systemName: "scope")
                                .font(.system(size: 9, weight: .heavy))
                            Text("GROUNDED")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(LinearGradient.diagonal))
                    }
                }
                if let summary = r.summary, !summary.isEmpty {
                    Text(summary)
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let model = r.aiModel, let ms = r.processingTimeMs {
                    Text("\(model) · \(ms) ms")
                        .font(EType.micro.monospacedDigit())
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }

        // Issues — honest empty state when none
        if r.issues.isEmpty {
            EusoEmptyState(
                systemImage: "checkmark.shield.fill",
                title: "No faults detected",
                subtitle: "ESANG couldn't see any visible damage, wear, or fault in this photo. Re-shoot from another angle if you suspect an issue."
            )
            .padding(.top, Space.s2)
        } else {
            ForEach(r.issues) { issue in
                issueRow(issue)
            }
        }

        // Top-level recommendations
        if !r.recommendations.isEmpty {
            ActiveCard {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("RECOMMENDATIONS")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    ForEach(r.recommendations, id: \.self) { rec in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(LinearGradient.diagonal)
                            Text(rec)
                                .font(EType.caption)
                                .foregroundStyle(palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        // Warnings — surfaced verbatim
        if !r.warnings.isEmpty {
            ActiveCard {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("WARNINGS")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    ForEach(r.warnings, id: \.self) { w in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Brand.warning)
                            Text(w)
                                .font(EType.caption)
                                .foregroundStyle(palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func issueRow(_ issue: ZeunMechanicsAPI.PartDiagnosisIssue) -> some View {
        let pct = Int((issue.confidence * 100).rounded())
        return ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(issue.label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.s2)
                    Text("\(pct)%")
                        .font(EType.bodyStrong.monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                }
                HStack(spacing: 6) {
                    if let sev = issue.severity {
                        StatusPill(text: sev, kind: severityPillKind(sev))
                    }
                    // Confidence meter — honest 0..1 → bar fill.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.bgCardSoft)
                            Capsule()
                                .fill(LinearGradient.diagonal)
                                .frame(width: max(0, min(1, issue.confidence)) * geo.size.width)
                        }
                    }
                    .frame(height: 6)
                }
                if let rec = issue.recommendation, !rec.isEmpty {
                    Text(rec)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Bottom CTA

    private var bottomCTA: some View {
        VStack {
            CTAButton(
                title: store.isDiagnosing ? "Diagnosing…" : "Diagnose part",
                action: { Task { await store.diagnose() } },
                isLoading: store.isDiagnosing
            )
            .opacity(store.hasPhoto ? 1 : 0.5)
            .disabled(!store.hasPhoto || store.isDiagnosing)
            if store.isDiagnosing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("ESANG is reading the photo…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            } else {
                Text("Vision-grounded read via zeunMechanics.diagnosePart. ESANG reports only faults it can actually see.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.s4)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(palette.bgPage)
    }

    private func severityPillKind(_ s: String) -> StatusPill.Kind {
        switch s.uppercased() {
        case "LOW":      return .success
        case "MEDIUM":   return .warning
        case "HIGH":     return .danger
        case "CRITICAL": return .danger
        default:         return .neutral
        }
    }
}

/// Registry-facing wrapper. Mirrors the `MeSupportScreen(theme:)` /
/// `CatalystMaintenanceZeunScreen(theme:)` shape so the screen can be
/// painted by the A→Z registry walker with a palette injected. The
/// production reach is through `MeZeunView` (driver Me-hub · Zeun),
/// presented as an `.eusoSheet()` exactly like its sibling Zeun
/// surfaces — so it's gated to the equipment role the same way they are.
struct MeZeunDiagnoseScreen: View {
    let theme: Theme.Palette
    var body: some View {
        ZeunPartDiagnosisScreen()
            .environment(\.palette, theme)
    }
}

// MARK: - Previews

#Preview("Part Diagnosis · Dark") {
    ZeunPartDiagnosisScreen()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("Breakdown Reporter · Dark") {
    ZeunBreakdownReporter()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("Provider Network · Dark") {
    ZeunProviderNetwork()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("Provider Network · Light") {
    ZeunProviderNetwork()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}

// MARK: - In-app SFSafariViewController for provider websites

/// Hosts a provider/mechanic shop website in an in-app modal so the
/// "globe" contact row doesn't actually kick the driver out to the
/// system Safari. SFSafariViewController preserves cookies + paywall
/// sessions exactly like Safari does — it's just chromed as a Zeun
/// modal.
private struct ZeunInAppSafari: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let cfg = SFSafariViewController.Configuration()
        cfg.entersReaderIfAvailable = false
        cfg.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: cfg)
        vc.dismissButtonStyle = .done
        vc.preferredControlTintColor = UIColor(Brand.magenta)
        return vc
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
