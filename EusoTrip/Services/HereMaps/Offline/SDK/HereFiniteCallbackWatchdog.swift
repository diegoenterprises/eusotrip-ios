//
//  HereFiniteCallbackWatchdog.swift
//  EusoTrip
//
//  Exactly-once boundary for finite native callbacks. HERE may complete on an
//  arbitrary queue, after cancellation, or not at all. This gate gives every
//  one-shot bridge one bounded waiter and makes late callbacks harmless.
//

import Foundation

enum HereFiniteCallbackWatchdogMisuse: Error, Equatable, Sendable {
    case waiterAlreadyInstalled
}

final class HereFiniteCallbackWatchdog<Value>: @unchecked Sendable {
    typealias TimeoutFailure = @Sendable () -> any Error

    private let lock = NSLock()
    private let timeout: TimeInterval
    private let timeoutIsValid: Bool
    private let timeoutQueue: DispatchQueue
    private let timeoutFailure: TimeoutFailure

    private var continuation: CheckedContinuation<Value, any Error>?
    private var terminalResult: Result<Value, any Error>?
    private var timeoutWorkItem: DispatchWorkItem?
    private var timeoutGeneration: UUID?
    private var interruptionAction: (() -> Void)?
    private var terminalRequiresInterruption = false
    private var waiterInstalled = false
    private var timeoutSuspended = false

    init(
        timeout: TimeInterval,
        timeoutQueue: DispatchQueue = DispatchQueue(
            label: "com.eusotrip.here-finite-callback-watchdog",
            qos: .utility
        ),
        timeoutFailure: @escaping TimeoutFailure
    ) {
        timeoutIsValid = timeout.isFinite && timeout > 0
        self.timeout = timeoutIsValid ? timeout : 0.001
        self.timeoutQueue = timeoutQueue
        self.timeoutFailure = timeoutFailure
    }

    func wait(
        interruptNativeOperation: (() -> Void)? = nil
    ) async throws -> Value {
        if !timeoutIsValid {
            finish(
                .failure(timeoutFailure()),
                interruptNativeOperation: true
            )
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                install(
                    continuation,
                    interruptionAction: interruptNativeOperation,
                    taskAlreadyCancelled: Task.isCancelled
                )
            }
        } onCancel: { [weak self] in
            self?.interrupt()
        }
    }

    @discardableResult
    func resolve(_ result: Result<Value, any Error>) -> Bool {
        finish(result, interruptNativeOperation: false)
    }

    @discardableResult
    func succeed(_ value: Value) -> Bool {
        resolve(.success(value))
    }

    @discardableResult
    func fail(_ error: any Error) -> Bool {
        resolve(.failure(error))
    }

    /// Extends an inactivity deadline when a finite transfer reports progress.
    func heartbeat() {
        lock.lock()
        guard waiterInstalled,
              terminalResult == nil,
              !timeoutSuspended else {
            lock.unlock()
            return
        }
        armTimeoutLocked()
        lock.unlock()
    }

    /// An intentionally paused transfer has no progress callbacks and must not
    /// be mistaken for a hung operation.
    func suspendTimeout() {
        lock.lock()
        timeoutSuspended = true
        let workItem = timeoutWorkItem
        timeoutWorkItem = nil
        timeoutGeneration = nil
        lock.unlock()
        workItem?.cancel()
    }

    func resumeTimeout() {
        lock.lock()
        guard timeoutSuspended else {
            lock.unlock()
            return
        }
        timeoutSuspended = false
        if waiterInstalled, terminalResult == nil {
            armTimeoutLocked()
        }
        lock.unlock()
    }

    @discardableResult
    func interrupt() -> Bool {
        finish(.failure(CancellationError()), interruptNativeOperation: true)
    }

    private func install(
        _ continuation: CheckedContinuation<Value, any Error>,
        interruptionAction: (() -> Void)?,
        taskAlreadyCancelled: Bool
    ) {
        lock.lock()
        guard !waiterInstalled else {
            lock.unlock()
            continuation.resume(
                throwing: HereFiniteCallbackWatchdogMisuse.waiterAlreadyInstalled
            )
            return
        }
        waiterInstalled = true
        if let terminalResult {
            let action = terminalRequiresInterruption ? interruptionAction : nil
            terminalRequiresInterruption = false
            lock.unlock()
            action?()
            continuation.resume(with: terminalResult)
            return
        }
        self.continuation = continuation
        self.interruptionAction = interruptionAction
        if !timeoutSuspended {
            armTimeoutLocked()
        }
        lock.unlock()

        if taskAlreadyCancelled {
            interrupt()
        }
    }

    private func armTimeoutLocked() {
        timeoutWorkItem?.cancel()
        let generation = UUID()
        let workItem = DispatchWorkItem { [weak self] in
            self?.expire(generation: generation)
        }
        timeoutWorkItem = workItem
        timeoutGeneration = generation
        timeoutQueue.asyncAfter(
            deadline: .now() + timeout,
            execute: workItem
        )
    }

    private func expire(generation: UUID) {
        finish(
            .failure(timeoutFailure()),
            interruptNativeOperation: true,
            expectedTimeoutGeneration: generation
        )
    }

    @discardableResult
    private func finish(
        _ result: Result<Value, any Error>,
        interruptNativeOperation: Bool,
        expectedTimeoutGeneration: UUID? = nil
    ) -> Bool {
        lock.lock()
        if let expectedTimeoutGeneration,
           timeoutGeneration != expectedTimeoutGeneration {
            lock.unlock()
            return false
        }
        guard terminalResult == nil else {
            lock.unlock()
            return false
        }
        terminalResult = result
        terminalRequiresInterruption = interruptNativeOperation
        let continuation = continuation
        self.continuation = nil
        let workItem = timeoutWorkItem
        timeoutWorkItem = nil
        timeoutGeneration = nil
        let action = interruptNativeOperation ? interruptionAction : nil
        if action != nil {
            terminalRequiresInterruption = false
        }
        interruptionAction = nil
        lock.unlock()

        workItem?.cancel()
        action?()
        continuation?.resume(with: result)
        return true
    }
}
