//
//  ScopedAsyncFlightRegistry.swift
//  EusoTrip
//
//  Coalesces identical async reads while keeping each caller's cancellation
//  and deadline independent. All lifecycle state is main-actor isolated so a
//  waiter can never miss completion between registration and suspension.
//


import Foundation

@MainActor
final class ScopedAsyncFlightRegistry<Key: Hashable, Value> {
    private final class Waiter {
        let id = UUID()
        let timeoutValue: Value
        var continuation: CheckedContinuation<Value, Never>?
        var timeoutTask: Task<Void, Never>?
        var isSettled = false

        init(timeoutValue: Value) {
            self.timeoutValue = timeoutValue
        }
    }

    private final class Flight {
        let id = UUID()
        let task: Task<Value, Never>
        var waiters: [UUID: Waiter] = [:]

        init(task: Task<Value, Never>) {
            self.task = task
        }
    }

    private let clock = ContinuousClock()
    private var flights: [Key: Flight] = [:]

    /// Completion monitors remain retained until their provider task has
    /// actually stopped. This owns/drains cancellation even after the last
    /// waiter leaves and the key becomes available for a fresh request.
    private var completionMonitors: [UUID: Task<Void, Never>] = [:]

    var activeFlightCount: Int { flights.count }

    func value(
        for key: Key,
        deadline: ContinuousClock.Instant,
        timeoutValue: Value,
        operation: @escaping @MainActor () async -> Value
    ) async -> Value {
        guard deadline > clock.now else { return timeoutValue }

        let flight: Flight
        if let existing = flights[key] {
            flight = existing
        } else {
            let task = Task { @MainActor in
                await operation()
            }
            let created = Flight(task: task)
            flights[key] = created
            flight = created

            let flightID = created.id
            completionMonitors[flightID] = Task { @MainActor [weak self] in
                let result = await task.value
                self?.completeFlight(result, for: key, flightID: flightID)
            }
        }

        let waiter = Waiter(timeoutValue: timeoutValue)
        flight.waiters[waiter.id] = waiter
        let flightID = flight.id
        let waiterID = waiter.id

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                attach(
                    continuation,
                    to: waiter,
                    for: key,
                    flightID: flightID,
                    deadline: deadline
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(
                    waiterID,
                    for: key,
                    flightID: flightID
                )
            }
        }
    }

    /// Auth/session changes use this to release every caller immediately,
    /// cancel provider work, and keep completion monitors alive until each
    /// cancelled provider has genuinely returned.
    func cancelAll(returning value: Value) {
        let current = flights
        flights.removeAll()
        for flight in current.values {
            flight.task.cancel()
            for waiter in flight.waiters.values {
                settle(waiter, returning: value)
            }
            flight.waiters.removeAll()
        }
    }

    private func attach(
        _ continuation: CheckedContinuation<Value, Never>,
        to waiter: Waiter,
        for key: Key,
        flightID: UUID,
        deadline: ContinuousClock.Instant
    ) {
        guard !waiter.isSettled else {
            continuation.resume(returning: waiter.timeoutValue)
            return
        }
        guard let flight = flights[key],
              flight.id == flightID,
              flight.waiters[waiter.id] === waiter else {
            waiter.isSettled = true
            continuation.resume(returning: waiter.timeoutValue)
            return
        }

        waiter.continuation = continuation
        guard deadline > clock.now else {
            timeoutWaiter(waiter.id, for: key, flightID: flightID)
            return
        }

        waiter.timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.clock.sleep(until: deadline)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.timeoutWaiter(waiter.id, for: key, flightID: flightID)
        }
    }

    private func completeFlight(
        _ result: Value,
        for key: Key,
        flightID: UUID
    ) {
        completionMonitors[flightID] = nil
        guard let flight = flights[key], flight.id == flightID else { return }
        flights[key] = nil
        for waiter in flight.waiters.values {
            settle(waiter, returning: result)
        }
        flight.waiters.removeAll()
    }

    private func timeoutWaiter(
        _ waiterID: UUID,
        for key: Key,
        flightID: UUID
    ) {
        guard let flight = flights[key], flight.id == flightID,
              let waiter = flight.waiters.removeValue(forKey: waiterID) else {
            return
        }
        settle(waiter, returning: waiter.timeoutValue)
        cancelProviderIfUnobserved(flight, for: key)
    }

    private func cancelWaiter(
        _ waiterID: UUID,
        for key: Key,
        flightID: UUID
    ) {
        guard let flight = flights[key], flight.id == flightID,
              let waiter = flight.waiters.removeValue(forKey: waiterID) else {
            return
        }
        settle(waiter, returning: waiter.timeoutValue)
        cancelProviderIfUnobserved(flight, for: key)
    }

    private func cancelProviderIfUnobserved(_ flight: Flight, for key: Key) {
        guard flight.waiters.isEmpty else { return }
        flight.task.cancel()
        if flights[key]?.id == flight.id {
            flights[key] = nil
        }
    }

    private func settle(_ waiter: Waiter, returning value: Value) {
        guard !waiter.isSettled else { return }
        waiter.isSettled = true
        waiter.timeoutTask?.cancel()
        waiter.timeoutTask = nil
        let continuation = waiter.continuation
        waiter.continuation = nil
        continuation?.resume(returning: value)
    }
}
