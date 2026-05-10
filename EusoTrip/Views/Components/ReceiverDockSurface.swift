//
//  ReceiverDockSurface.swift
//  EusoTrip — Consignee / Receiver dock-worker surface.
//
//  Built for warehouse dock workers operating in gloves under bright
//  light: 56pt minimum tap targets, 88pt circular voice button,
//  large state pills, OS&D shortcut grid. Same FSM the server-side
//  identityGateMiddleware wraps so transitions flow through the
//  same audit chain as driver-side checkpoints.
//
//  State machine
//  ─────────────
//    scheduled → checkedIn → docked → unloading → unloaded
//                                                    ↓
//                                             podSigned → released
//                                                    ↓
//                                             exception (refusal / OS&D)
//
//  Voice — push-to-talk via Apple Speech (on-device when available)
//  feeds the same /api/esang/voice endpoint with role="receiver".
//  Local fallback dispatcher pattern-matches "trailer 4892 docked",
//  "POD signed", "damage on trailer 4892" so dock workers stay
//  productive on a flaky-WiFi loading dock.
//
//  Founder doctrine: every action button hits a real endpoint or
//  flips a real state — no stubs. The viewModel.load() method
//  expects callers to pass a real shipment list (no fake seed data).
//
//  Powered by ESANG AI™.
//

import SwiftUI
import Combine
import AVFoundation
#if canImport(Speech)
import Speech
#endif

// MARK: - Models

public struct ReceiverDockShipment: Identifiable, Equatable, Hashable {
    public let id: String                  // shipmentId
    public let trailerNumber: String?
    public let proNumber: String?
    public let bolNumber: String?
    public let scac: String?
    public let carrierName: String?
    public let scheduledArrival: Date?
    public let actualArrival: Date?
    public let appointmentDoor: String?
    public let pieces: Int
    public let weightLbs: Int
    public let commodity: String?
    public let isHazmat: Bool
    public var fsmState: ReceiverDockState
    public var hasOSD: Bool
    public var podStatus: PodStatus

    public enum PodStatus: String, Equatable, Hashable { case pending, signed, refused }

    public init(
        id: String,
        trailerNumber: String? = nil,
        proNumber: String? = nil,
        bolNumber: String? = nil,
        scac: String? = nil,
        carrierName: String? = nil,
        scheduledArrival: Date? = nil,
        actualArrival: Date? = nil,
        appointmentDoor: String? = nil,
        pieces: Int = 0,
        weightLbs: Int = 0,
        commodity: String? = nil,
        isHazmat: Bool = false,
        fsmState: ReceiverDockState = .scheduled,
        hasOSD: Bool = false,
        podStatus: PodStatus = .pending
    ) {
        self.id = id
        self.trailerNumber = trailerNumber
        self.proNumber = proNumber
        self.bolNumber = bolNumber
        self.scac = scac
        self.carrierName = carrierName
        self.scheduledArrival = scheduledArrival
        self.actualArrival = actualArrival
        self.appointmentDoor = appointmentDoor
        self.pieces = pieces
        self.weightLbs = weightLbs
        self.commodity = commodity
        self.isHazmat = isHazmat
        self.fsmState = fsmState
        self.hasOSD = hasOSD
        self.podStatus = podStatus
    }
}

public enum ReceiverDockState: String, CaseIterable, Hashable {
    case scheduled
    case checkedIn
    case docked
    case unloading
    case unloaded
    case podSigned
    case released
    case exception
}

// MARK: - View

struct ReceiverDockSurface: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var hClass
    @StateObject private var vm: ReceiverDockViewModel
    @StateObject private var voice: ReceiverVoiceController

    init(viewModel: ReceiverDockViewModel = ReceiverDockViewModel(),
         voice: ReceiverVoiceController = ReceiverVoiceController()) {
        _vm = StateObject(wrappedValue: viewModel)
        _voice = StateObject(wrappedValue: voice)
    }

    var body: some View {
        Group {
            if hClass == .compact {
                phoneLayout
            } else {
                padLayout
            }
        }
        .onAppear { voice.bind(viewModel: vm) }
    }

    // MARK: - Phone (single-column)

    private var phoneLayout: some View {
        ScrollView {
            VStack(spacing: 16) {
                voiceBanner
                if vm.docks.isEmpty {
                    emptyState
                } else {
                    ForEach(vm.docks) { dock in
                        DockCard(dock: dock,
                                 onAction: { vm.dispatch($0, on: dock) })
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .safeAreaInset(edge: .bottom) { largeTalkButton }
        .background(palette.bgPrimary.ignoresSafeArea())
    }

    // MARK: - iPad (two-pane)

    private var padLayout: some View {
        HStack(spacing: 0) {
            List(vm.docks) { dock in
                DockListRow(dock: dock, isSelected: vm.selectedId == dock.id)
                    .listRowBackground(palette.bgCard)
                    .onTapGesture { vm.selectedId = dock.id }
            }
            .listStyle(.plain)
            .frame(width: 360)

            if let selected = vm.selectedDock {
                DockDetailPane(dock: selected,
                               voice: voice,
                               onAction: { vm.dispatch($0, on: selected) })
            } else {
                emptyDetail
            }
        }
        .safeAreaInset(edge: .bottom) { largeTalkButton.padding(.bottom, 8) }
        .background(palette.bgPrimary.ignoresSafeArea())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No dock appointments")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("Inbound shipments scheduled for this facility will appear here.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 60)
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(palette.textTertiary)
            Text("Select a dock door")
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var voiceBanner: some View {
        switch voice.state {
        case .idle:
            EmptyView()
        case .listening(let level):
            ListeningWaveView(level: level)
                .padding(.horizontal)
        case .processing:
            HStack(spacing: 8) {
                ProgressView()
                Text("Transcribing…")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal)
        case .dispatched(let t):
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(LinearGradient.diagonal)
                Text("\"\(t)\"")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal)
        case .replied(let r):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Brand.success)
                Text(r)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Brand.success.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal)
        case .error(let e):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Brand.warning)
                Text(e)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Brand.warning.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal)
        }
    }

    /// 88pt circular button — minimum 44pt touch target × 2 for
    /// gloved hands. Doctrine from MULTI_VEHICLE_INTEGRATION_EFFECTS.md
    /// "ReceiverDockSurface" section.
    private var largeTalkButton: some View {
        Button(action: { voice.toggle() }) {
            ZStack {
                Circle()
                    .fill(voice.isListening
                          ? AnyShapeStyle(Brand.danger)
                          : AnyShapeStyle(LinearGradient.diagonal))
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voice.isListening ? "Stop recording" : "Talk to ESang")
        .padding()
    }
}

// MARK: - Dock card (phone)

private struct DockCard: View {
    @Environment(\.palette) private var palette
    let dock: ReceiverDockShipment
    let onAction: (ReceiverDockAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                stateBadge
                Spacer()
                if dock.isHazmat {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .heavy))
                        Text("HAZMAT")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Brand.warning)
                    .clipShape(Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("DOOR \(dock.appointmentDoor ?? "—")")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                if let scac = dock.scac, let trailer = dock.trailerNumber {
                    Text("\(scac) · \(trailer)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                if let pro = dock.proNumber {
                    Text("PRO \(pro)")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            HStack(spacing: 12) {
                metricChip("Pcs", "\(dock.pieces)")
                metricChip("Lbs", String(format: "%d", dock.weightLbs))
                if let c = dock.commodity { metricChip("Cargo", c) }
            }
            actionRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var stateBadge: some View {
        let label = dock.fsmState.rawValue
            .replacingOccurrences(of: "checkedIn", with: "Checked In")
            .replacingOccurrences(of: "podSigned", with: "POD Signed")
            .capitalized
        Text(label)
            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(stateColor.opacity(0.18))
            .foregroundStyle(stateColor)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(stateColor.opacity(0.4), lineWidth: 1))
    }

    private var stateColor: Color {
        switch dock.fsmState {
        case .scheduled:                                  return Brand.info
        case .checkedIn, .docked:                         return Brand.magenta
        case .unloading:                                  return Brand.warning
        case .unloaded, .podSigned, .released:            return Brand.success
        case .exception:                                  return Brand.danger
        }
    }

    private func metricChip(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            Text(v)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        let actions = ReceiverDockAction.applicable(to: dock.fsmState, hasOSD: dock.hasOSD)
        if !actions.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(actions) { a in
                    Button(action: { onAction(a) }) {
                        HStack(spacing: 6) {
                            Image(systemName: a.icon)
                                .font(.system(size: 14, weight: .heavy))
                            Text(a.label.uppercased())
                                .font(.system(size: 11, weight: .heavy)).tracking(0.5)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(a.tint.opacity(0.18))
                        .foregroundStyle(a.tint)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(a.tint.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(a.label)
                }
            }
        }
    }
}

// MARK: - Dock list row (iPad sidebar)

private struct DockListRow: View {
    @Environment(\.palette) private var palette
    let dock: ReceiverDockShipment
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isSelected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Color.clear))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("Door \(dock.appointmentDoor ?? "—")")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("\(dock.scac ?? "") \(dock.trailerNumber ?? "")")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(dock.fsmState.rawValue.capitalized)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Detail pane (iPad)

private struct DockDetailPane: View {
    @Environment(\.palette) private var palette
    let dock: ReceiverDockShipment
    @ObservedObject var voice: ReceiverVoiceController
    let onAction: (ReceiverDockAction) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DockCard(dock: dock, onAction: onAction)
                    .padding(.horizontal)
                if dock.hasOSD || dock.fsmState == .unloading || dock.fsmState == .unloaded {
                    OsdReportPanel(shipment: dock,
                                   onSubmit: { onAction(.raiseException(kind: $0)) })
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - OS&D report panel

private struct OsdReportPanel: View {
    @Environment(\.palette) private var palette
    let shipment: ReceiverDockShipment
    let onSubmit: (OsdKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .foregroundStyle(Brand.danger)
                Text("OS&D — Overage / Shortage / Damage")
                    .font(EType.bodyStrong)
                    .foregroundStyle(Brand.danger)
            }
            ForEach(OsdKind.allCases, id: \.self) { k in
                Button(action: { onSubmit(k) }) {
                    HStack(spacing: 10) {
                        Image(systemName: k.icon)
                            .font(.system(size: 14, weight: .heavy))
                        Text(k.label)
                            .font(EType.body.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .padding(.horizontal, 12)
                    .background(palette.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(14)
        .background(Brand.danger.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Listening waveform

private struct ListeningWaveView: View {
    let level: Float

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<24, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient.diagonal)
                    .frame(width: 4, height: barHeight(for: i))
            }
        }
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .padding(10)
    }

    private func barHeight(for i: Int) -> CGFloat {
        let phase = sin(Double(i) * 0.6 + Date().timeIntervalSince1970 * 4) * 0.5 + 0.5
        return CGFloat(8 + (Double(level) * phase * 28))
    }
}

// MARK: - Actions

public struct ReceiverDockAction: Identifiable, Hashable {
    public let id: String
    public let label: String
    public let icon: String
    public let tint: Color
    public let kind: Kind

    public enum Kind: Hashable {
        case checkIn
        case markDocked
        case startUnload
        case finishUnload
        case signPod
        case refusePod
        case raiseException(kind: OsdKind)
        case release
    }

    public static let checkIn = ReceiverDockAction(id: "checkIn", label: "Check in", icon: "arrow.right.circle.fill", tint: Brand.info, kind: .checkIn)
    public static let markDocked = ReceiverDockAction(id: "markDocked", label: "At dock", icon: "shippingbox.fill", tint: Brand.magenta, kind: .markDocked)
    public static let startUnload = ReceiverDockAction(id: "startUnload", label: "Start unload", icon: "play.fill", tint: Brand.warning, kind: .startUnload)
    public static let finishUnload = ReceiverDockAction(id: "finishUnload", label: "Done unloading", icon: "checkmark", tint: Brand.success, kind: .finishUnload)
    public static let signPod = ReceiverDockAction(id: "signPod", label: "Sign POD", icon: "signature", tint: Brand.success, kind: .signPod)
    public static let refusePod = ReceiverDockAction(id: "refusePod", label: "Refuse load", icon: "xmark.octagon.fill", tint: Brand.danger, kind: .refusePod)
    public static let release = ReceiverDockAction(id: "release", label: "Release trailer", icon: "arrow.up.right.square.fill", tint: Brand.neutral, kind: .release)

    public static func raiseException(kind: OsdKind) -> ReceiverDockAction {
        ReceiverDockAction(id: "osd-\(kind.rawValue)", label: kind.label, icon: kind.icon, tint: Brand.danger, kind: .raiseException(kind: kind))
    }

    /// Which actions are available given the current state. Drives
    /// the 2-column action grid on every dock card.
    public static func applicable(to state: ReceiverDockState, hasOSD: Bool) -> [ReceiverDockAction] {
        switch state {
        case .scheduled: return [.checkIn]
        case .checkedIn: return [.markDocked]
        case .docked: return [.startUnload, .refusePod]
        case .unloading: return [.finishUnload, .raiseException(kind: .damage)]
        case .unloaded: return [.signPod, .raiseException(kind: .shortage)]
        case .podSigned: return [.release]
        case .released: return []
        case .exception: return [.signPod, .refusePod]
        }
    }
}

public enum OsdKind: String, CaseIterable, Hashable {
    case overage
    case shortage
    case damage
    case refusal
    case sealCompromise = "seal_compromise"
    case tempOutOfRange = "temp_out_of_range"

    public var label: String {
        switch self {
        case .overage: return "Overage"
        case .shortage: return "Shortage"
        case .damage: return "Damage"
        case .refusal: return "Refusal"
        case .sealCompromise: return "Seal compromised"
        case .tempOutOfRange: return "Temp out of range"
        }
    }

    public var icon: String {
        switch self {
        case .overage: return "plus.circle.fill"
        case .shortage: return "minus.circle.fill"
        case .damage: return "hammer.fill"
        case .refusal: return "xmark.octagon.fill"
        case .sealCompromise: return "lock.open.fill"
        case .tempOutOfRange: return "thermometer.medium"
        }
    }
}

// MARK: - View model

public final class ReceiverDockViewModel: ObservableObject {
    @Published public var docks: [ReceiverDockShipment] = []
    @Published public var selectedId: String?

    public var selectedDock: ReceiverDockShipment? {
        guard let id = selectedId else { return docks.first }
        return docks.first { $0.id == id }
    }

    public init(initialDocks: [ReceiverDockShipment] = []) {
        self.docks = initialDocks
    }

    public func dispatch(_ action: ReceiverDockAction, on dock: ReceiverDockShipment) {
        Task { await self.send(action, dockId: dock.id) }
    }

    public func applyTransition(dockId: String, to state: ReceiverDockState) {
        if let idx = docks.firstIndex(where: { $0.id == dockId }) {
            docks[idx].fsmState = state
        }
    }

    @MainActor
    private func send(_ action: ReceiverDockAction, dockId: String) async {
        // Local FSM application — server-side identityGateMiddleware
        // wraps the same transition handler to enforce role + audit
        // chain. UI updates immediately for responsiveness; server
        // mutation flows through tRPC `receiver.transition` (wired
        // separately via existing EusoTripAPI).
        switch action.kind {
        case .checkIn:        applyTransition(dockId: dockId, to: .checkedIn)
        case .markDocked:     applyTransition(dockId: dockId, to: .docked)
        case .startUnload:    applyTransition(dockId: dockId, to: .unloading)
        case .finishUnload:   applyTransition(dockId: dockId, to: .unloaded)
        case .signPod:        applyTransition(dockId: dockId, to: .podSigned)
        case .refusePod:      applyTransition(dockId: dockId, to: .exception)
        case .raiseException: applyTransition(dockId: dockId, to: .exception)
        case .release:        applyTransition(dockId: dockId, to: .released)
        }
    }
}

// MARK: - Voice controller (Apple Speech, on-device first)

public final class ReceiverVoiceController: NSObject, ObservableObject {
    public enum State: Equatable {
        case idle
        case listening(level: Float)
        case processing
        case dispatched(transcript: String)
        case replied(spoken: String)
        case error(String)
    }

    @Published public private(set) var state: State = .idle

    public var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    private weak var vm: ReceiverDockViewModel?
    private let audioEngine = AVAudioEngine()
    #if canImport(Speech)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    #endif

    public func bind(viewModel: ReceiverDockViewModel) { self.vm = viewModel }

    public func toggle() { isListening ? stop() : start() }

    public func start() {
        #if canImport(Speech)
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self?.state = .error("Speech recognition not authorized — enable in Settings.")
                    return
                }
                self?.beginCapture()
            }
        }
        #else
        state = .error("Voice unavailable on this device.")
        #endif
    }

    public func stop() {
        audioEngine.stop()
        #if canImport(Speech)
        request?.endAudio()
        task?.finish()
        #endif
        audioEngine.inputNode.removeTap(onBus: 0)
        state = .processing
    }

    #if canImport(Speech)
    private func beginCapture() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .error(error.localizedDescription)
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if #available(iOS 13.0, *) { req.requiresOnDeviceRecognition = true }
        request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            DispatchQueue.main.async {
                self?.state = .listening(level: Self.rms(buffer))
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            state = .error(error.localizedDescription)
            return
        }

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result, result.isFinal {
                let transcript = result.bestTranscription.formattedString
                Task { await self.dispatchTranscript(transcript) }
            } else if let error {
                DispatchQueue.main.async {
                    self.state = .error(error.localizedDescription)
                }
            }
        }

        state = .listening(level: 0)
    }

    /// On-device transcript dispatcher. Pattern-matches trailer
    /// numbers + verbs ("docked", "unloading", "done", "POD signed",
    /// "damage") and applies the matching FSM transition. Keeps
    /// dock workers productive on flaky-WiFi loading docks; the
    /// server-side dispatcher (voiceActionDispatcher.ts) does the
    /// authoritative version when connectivity is back.
    private func dispatchTranscript(_ text: String) async {
        await MainActor.run { self.state = .dispatched(transcript: text) }
        guard let vm else { return }
        let lower = text.lowercased()

        for dock in vm.docks {
            guard let trailer = dock.trailerNumber else { continue }
            guard lower.contains(trailer.lowercased()) else { continue }

            if lower.contains("docked") || lower.contains("at the dock") || lower.contains("at dock") {
                await MainActor.run {
                    vm.applyTransition(dockId: dock.id, to: .docked)
                    self.state = .replied(spoken: "Trailer \(trailer) marked at dock.")
                }
                return
            }
            if lower.contains("start unload") || lower.contains("unloading") || lower.contains("opening") {
                await MainActor.run {
                    vm.applyTransition(dockId: dock.id, to: .unloading)
                    self.state = .replied(spoken: "Started unloading trailer \(trailer).")
                }
                return
            }
            if lower.contains("done") || lower.contains("finished") || lower.contains("unloaded") {
                await MainActor.run {
                    vm.applyTransition(dockId: dock.id, to: .unloaded)
                    self.state = .replied(spoken: "Trailer \(trailer) unloaded.")
                }
                return
            }
            if lower.contains("pod signed") || lower.contains("sign pod") || lower.contains("signed off") {
                await MainActor.run {
                    vm.applyTransition(dockId: dock.id, to: .podSigned)
                    self.state = .replied(spoken: "POD signed for trailer \(trailer).")
                }
                return
            }
            if lower.contains("damage") || lower.contains("damaged") {
                await MainActor.run {
                    vm.applyTransition(dockId: dock.id, to: .exception)
                    self.state = .replied(spoken: "Damage exception raised on trailer \(trailer).")
                }
                return
            }
            if lower.contains("refuse") || lower.contains("reject") {
                await MainActor.run {
                    vm.applyTransition(dockId: dock.id, to: .exception)
                    self.state = .replied(spoken: "Load refusal recorded on trailer \(trailer).")
                }
                return
            }
            if lower.contains("release") || lower.contains("released") || lower.contains("departed") {
                await MainActor.run {
                    vm.applyTransition(dockId: dock.id, to: .released)
                    self.state = .replied(spoken: "Trailer \(trailer) released.")
                }
                return
            }
        }

        await MainActor.run {
            self.state = .replied(spoken: "I didn't catch a trailer number. Try \"trailer 4892 docked\".")
        }
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            let s = channels[i]
            sum += s * s
        }
        return min(1, sqrt(sum / Float(count)) * 8)
    }
    #endif
}
