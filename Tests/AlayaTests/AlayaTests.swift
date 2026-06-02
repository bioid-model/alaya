import Foundation
import Testing
@testable import Alaya

@Suite struct InMemorySubstrateTests {

    @Test func persistAndRecallReturnsLatestFirst() async throws {
        let substrate = InMemorySubstrate()
        let s1 = ColoredStimulus(
            stimulus: Stimulus(mediaType: MediaType.textPlain, data: Data("a".utf8)),
            valence: .neutral
        )
        let s2 = ColoredStimulus(
            stimulus: Stimulus(mediaType: MediaType.textPlain, data: Data("b".utf8)),
            valence: .neutral
        )
        try await substrate.persist(s1)
        try await substrate.persist(s2)

        let results = try await substrate.recall(
            query: RecallQuery(mediaTypes: [MediaType.textPlain], limit: 8)
        )
        #expect(results.count == 2)
        #expect(results.first?.colored.stimulus.id == s2.stimulus.id)
        #expect(results.last?.colored.stimulus.id == s1.stimulus.id)
    }

    @Test func recallFiltersByMediaType() async throws {
        let substrate = InMemorySubstrate()
        let text = ColoredStimulus(
            stimulus: Stimulus(mediaType: MediaType.textPlain, data: Data()),
            valence: .neutral
        )
        let audio = ColoredStimulus(
            stimulus: Stimulus(mediaType: MediaType.audioPCM, data: Data()),
            valence: .neutral
        )
        try await substrate.persist(text)
        try await substrate.persist(audio)

        let results = try await substrate.recall(
            query: RecallQuery(mediaTypes: [MediaType.audioPCM], limit: 8)
        )
        #expect(results.count == 1)
        #expect(results.first?.colored.stimulus.mediaType == MediaType.audioPCM)
    }

    @Test func provideCognitionContextBundlesRecallAndBija() async throws {
        let substrate = InMemorySubstrate()
        let trigger = ColoredStimulus(
            stimulus: Stimulus(mediaType: MediaType.textPlain, data: Data("trigger".utf8)),
            valence: .neutral
        )
        try await substrate.persist(trigger)
        let karman = Karman(
            action: Action(kind: MediaType.textPlain, payload: Data()),
            origin: .deliberate,
            provenance: .stimulus(trigger.stimulus.id)
        )
        try await substrate.record(
            Bija(
                karmanRef: karman.id,
                valenceAtIssue: trigger.valence,
                summary: .of(karman)
            )
        )

        let context = try await substrate.provideCognitionContext(for: trigger)
        #expect(context.trigger.stimulus.id == trigger.stimulus.id)
        #expect(context.recall.contains(where: { $0.colored.stimulus.id == trigger.stimulus.id }))
        #expect(context.recentBija.contains(where: { $0.karmanRef == karman.id }))
    }
}

@Suite struct FileBackedSubstrateTests {

    @Test func closeIsIdempotentAndReopenReplaysHistory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bioid-alaya-tests-\(UUID().uuidString)", isDirectory: true)
        let colored = ColoredStimulus(
            stimulus: Stimulus(mediaType: MediaType.textPlain, data: Data("persisted".utf8)),
            valence: .neutral
        )

        let substrate = try FileBackedSubstrate(directory: directory)
        try await substrate.persist(colored)
        try await substrate.close()
        try await substrate.close()

        let reopened = try FileBackedSubstrate(directory: directory)
        let results = try await reopened.recall(
            query: RecallQuery(mediaTypes: [MediaType.textPlain], limit: 8)
        )

        #expect(results.count == 1)
        #expect(results.first?.colored.stimulus.id == colored.stimulus.id)

        try await reopened.close()
        try FileManager.default.removeItem(at: directory)
    }
}

@Suite struct ControlLoopTests {

    @Test func loopRunsAllStagesAndRecordsBija() async throws {
        let stimulus = Stimulus(mediaType: MediaType.textPlain, data: Data("hi".utf8))
        let sense = OneShotSense(stimulus: stimulus)
        let manas = TestIdentityManas()
        let substrate = InMemorySubstrate()
        let cognizer = PassthroughCognizer()
        let effector = CapturingEffector()

        try await runControlLoop(
            sense: sense,
            bias: manas,
            substrate: substrate,
            cognizer: cognizer,
            karmanGate: manas,
            effector: effector
        )

        let executed = await effector.captured
        #expect(executed.count == 1)
        #expect(executed.first?.action.kind == MediaType.textPlain)

        let bija = try await substrate.recall(
            query: RecallQuery(mediaTypes: [MediaType.textPlain], limit: 8)
        )
        #expect(bija.count == 1)
    }
}

private final class OneShotSense: Sense {
    let emittedMediaTypes: Set<MediaType>
    private let stimulus: Stimulus

    init(stimulus: Stimulus) {
        self.stimulus = stimulus
        self.emittedMediaTypes = [stimulus.mediaType]
    }

    func stimuli() -> AsyncThrowingStream<Stimulus, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(stimulus)
            continuation.finish()
        }
    }

    func shutdown() async {}
}

private struct TestIdentityManas: Bias, KarmanGate, Sendable {
    func color(_ stimulus: Stimulus) async throws -> ColoredStimulus {
        ColoredStimulus(stimulus: stimulus, valence: .neutral)
    }
    func issue(
        _ action: Action,
        origin: KarmanOrigin,
        provenance: ProvenanceRef
    ) async throws -> Karman {
        Karman(action: action, origin: origin, provenance: provenance)
    }
}

private struct PassthroughCognizer: Cognizer, Sendable {
    func cognize(_ context: CognitionContext) async throws -> Action {
        Action(
            kind: context.trigger.stimulus.mediaType,
            payload: context.trigger.stimulus.data
        )
    }
}

private actor CapturingEffector: Effector {
    let acceptedKinds: Set<MediaType> = [.textPlain]
    private(set) var captured: [Karman] = []

    func execute(_ karman: Karman) async throws {
        captured.append(karman)
    }
}
