import Foundation
import BioidCore

/// A `Substrate` that holds all state in process memory.
///
/// `InMemorySubstrate` is the Phase 0 storehouse. It persists every
/// `ColoredStimulus` and every `Bija` in append-only buffers and
/// answers `recall(query:)` and `provideCognitionContext(for:)` from
/// those buffers. There is no on-disk persistence and no eviction —
/// the buffers grow until the process exits or `prune(maxStimuli:
/// maxBija:)` is called.
///
/// Use this implementation for harness, tests, and the bootstrap
/// loop. A durable implementation (file-backed, vector-indexed,
/// append-only log) replaces it without touching the rest of the
/// loop, because every consumer talks to `Substrate` through the
/// protocol.
public actor InMemorySubstrate: Substrate {

    private var stimuli: [ColoredStimulus] = []
    private var bija: [Bija] = []

    /// Maximum number of `RecollectedStimulus` and `Bija` to surface in
    /// `provideCognitionContext(for:)`. Sized for typical short-context
    /// cognition; tune at the composition root.
    private let contextRecallLimit: Int
    private let contextBijaLimit: Int

    public init(
        contextRecallLimit: Int = 8,
        contextBijaLimit: Int = 8
    ) {
        self.contextRecallLimit = contextRecallLimit
        self.contextBijaLimit = contextBijaLimit
    }

    public func persist(_ colored: ColoredStimulus) async throws {
        stimuli.append(colored)
    }

    public func record(_ bija: Bija) async throws {
        self.bija.append(bija)
    }

    public func recall(query: RecallQuery) async throws -> [RecollectedStimulus] {
        var results: [RecollectedStimulus] = []
        results.reserveCapacity(query.limit)
        for colored in stimuli.reversed() {
            if let since = query.since, colored.stimulus.observedAt < since {
                continue
            }
            if let mediaTypes = query.mediaTypes,
               !mediaTypes.contains(colored.stimulus.mediaType) {
                continue
            }
            results.append(RecollectedStimulus(colored: colored))
            if results.count >= query.limit { break }
        }
        return results
    }

    public func provideCognitionContext(
        for colored: ColoredStimulus
    ) async throws -> CognitionContext {
        let recall = try await recall(
            query: RecallQuery(
                mediaTypes: [colored.stimulus.mediaType],
                limit: contextRecallLimit
            )
        )
        let recentBija = Array(bija.suffix(contextBijaLimit))
        return CognitionContext(
            trigger: colored,
            recall: recall,
            recentBija: recentBija
        )
    }

    /// Drop oldest entries until each buffer fits the supplied caps.
    /// `nil` means "leave that buffer alone".
    public func prune(maxStimuli: Int? = nil, maxBija: Int? = nil) {
        if let cap = maxStimuli, stimuli.count > cap {
            stimuli.removeFirst(stimuli.count - cap)
        }
        if let cap = maxBija, bija.count > cap {
            self.bija.removeFirst(self.bija.count - cap)
        }
    }
}
