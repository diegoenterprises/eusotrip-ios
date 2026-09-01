//
//  AppRadioSilenceWatchState.swift
//  EusoTrip Pulse Watch App
//
//  Pure, source-testable ordering state for the policy mirrored from iPhone.
//

import Foundation

struct AppRadioSilenceWatchState: Equatable, Sendable {
    enum Transition: Equatable, Sendable {
        case stale
        case unchanged
        case engaged
        case released
    }

    private(set) var isEnforced: Bool
    private(set) var revision: Int
    private(set) var epoch: String?
    private(set) var retiredEpochs: Set<String>

    init(
        isEnforced: Bool = true,
        revision: Int = 0,
        epoch: String? = nil,
        retiredEpochs: Set<String> = []
    ) {
        self.isEnforced = isEnforced
        self.revision = max(0, revision)
        self.epoch = epoch?.isEmpty == false ? epoch : nil
        self.retiredEpochs = retiredEpochs
    }

    mutating func apply(
        enforced: Bool,
        revision nextRevision: Int,
        epoch nextEpoch: String
    ) -> Transition {
        guard !nextEpoch.isEmpty, nextRevision >= 0 else { return .stale }

        if nextEpoch != epoch {
            guard !retiredEpochs.contains(nextEpoch) else { return .stale }
            if let epoch { retiredEpochs.insert(epoch) }
            epoch = nextEpoch
            revision = nextRevision
            guard enforced != isEnforced else { return .unchanged }
            isEnforced = enforced
            return enforced ? .engaged : .released
        }

        guard nextRevision >= revision else { return .stale }
        guard nextRevision > revision else {
            return enforced == isEnforced ? .unchanged : .stale
        }

        revision = nextRevision
        guard enforced != isEnforced else { return .unchanged }
        isEnforced = enforced
        return enforced ? .engaged : .released
    }
}

struct AppRadioSilenceWatchLegacyState: Equatable, Sendable {
    let isEnforced: Bool?
    let revision: Int?
    let epoch: String?
    let retiredEpochs: [String]?

    static let empty = Self(
        isEnforced: nil,
        revision: nil,
        epoch: nil,
        retiredEpochs: nil
    )

    var hasAnyValue: Bool {
        isEnforced != nil || revision != nil || epoch != nil || retiredEpochs != nil
    }
}

private struct AppRadioSilenceWatchPersistedSnapshot: Codable {
    let version: Int
    let isEnforced: Bool
    let revision: Int
    let epoch: String?
    let retiredEpochs: [String]
}

enum AppRadioSilenceWatchPersistence {
    static let currentVersion = 1

    static func encode(_ state: AppRadioSilenceWatchState) throws -> Data {
        if let epoch = state.epoch {
            guard !epoch.isEmpty,
                  state.revision >= 0,
                  !state.retiredEpochs.contains(epoch),
                  state.retiredEpochs.allSatisfy({ !$0.isEmpty }) else {
                throw CocoaError(.coderInvalidValue)
            }
        } else {
            guard state.isEnforced,
                  state.revision == 0,
                  state.retiredEpochs.isEmpty else {
                throw CocoaError(.coderInvalidValue)
            }
        }
        let snapshot = AppRadioSilenceWatchPersistedSnapshot(
            version: currentVersion,
            isEnforced: state.isEnforced,
            revision: state.revision,
            epoch: state.epoch,
            retiredEpochs: state.retiredEpochs.sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// A present but malformed new-format snapshot never falls back to mutable
    /// legacy keys. It restores the closed default until the paired phone sends
    /// a new authoritative epoch/revision envelope.
    static func restore(
        snapshotData: Data?,
        legacy: AppRadioSilenceWatchLegacyState = .empty
    ) -> AppRadioSilenceWatchState {
        if let snapshotData {
            guard let snapshot = try? JSONDecoder().decode(
                AppRadioSilenceWatchPersistedSnapshot.self,
                from: snapshotData
            ),
            snapshot.version == currentVersion,
            snapshot.revision >= 0,
            snapshot.retiredEpochs.allSatisfy({ !$0.isEmpty }) else {
                return AppRadioSilenceWatchState()
            }
            if let epoch = snapshot.epoch {
                guard !epoch.isEmpty,
                      !snapshot.retiredEpochs.contains(epoch) else {
                    return AppRadioSilenceWatchState()
                }
            } else {
                guard snapshot.isEnforced,
                      snapshot.revision == 0,
                      snapshot.retiredEpochs.isEmpty else {
                    return AppRadioSilenceWatchState()
                }
            }
            return AppRadioSilenceWatchState(
                isEnforced: snapshot.isEnforced,
                revision: snapshot.revision,
                epoch: snapshot.epoch,
                retiredEpochs: Set(snapshot.retiredEpochs)
            )
        }

        guard legacy.hasAnyValue else { return AppRadioSilenceWatchState() }
        guard let isEnforced = legacy.isEnforced,
              let revision = legacy.revision,
              revision >= 0,
              let epoch = legacy.epoch,
              !epoch.isEmpty else {
            return AppRadioSilenceWatchState()
        }
        let retiredEpochs = Set(legacy.retiredEpochs ?? [])
        guard !retiredEpochs.contains(epoch),
              retiredEpochs.allSatisfy({ !$0.isEmpty }) else {
            return AppRadioSilenceWatchState()
        }
        return AppRadioSilenceWatchState(
            isEnforced: isEnforced,
            revision: revision,
            epoch: epoch,
            retiredEpochs: retiredEpochs
        )
    }
}
