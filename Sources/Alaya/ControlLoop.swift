import Foundation
import BioidCore

/// The Phase 0 BIOID control loop.
///
/// `runControlLoop` consumes `Stimulus` values from a `Sense`, colours
/// them via `Bias`, persists them in the `Substrate`, asks the
/// `Cognizer` to interpret each event, gates the resulting `Action`
/// through `KarmanGate`, dispatches the issued `Karman` to an
/// `Effector`, and closes the trace by recording a `Bija` in the
/// substrate.
///
///     Sense.stimuli  ─►  Bias.color
///                          │
///                          ▼
///                  Substrate.persist
///                          │
///                          ▼
///            Substrate.provideCognitionContext
///                          │
///                          ▼
///                    Cognizer.cognize
///                          │
///                          ▼
///                  KarmanGate.issue
///                          │
///                          ▼
///                   Effector.execute
///                          │
///                          ▼
///                   Substrate.record
///
/// The function returns when `sense.stimuli()` finishes. Cancellation
/// of the surrounding task aborts the loop at the next stimulus
/// boundary; `sense.shutdown()` is *not* called automatically — the
/// composition root owns shutdown.
///
/// Errors from any step propagate. There is no silent fallback: a
/// failure to colour, persist, cognize, gate, execute, or record
/// terminates the loop so the cause is visible.
public func runControlLoop(
    sense: any Sense,
    bias: any Bias,
    substrate: any Substrate,
    cognizer: any Cognizer,
    karmanGate: any KarmanGate,
    effector: any Effector
) async throws {
    for try await stimulus in sense.stimuli() {
        try Task.checkCancellation()

        let colored = try await bias.color(stimulus)
        try await substrate.persist(colored)

        let context = try await substrate.provideCognitionContext(for: colored)
        let action = try await cognizer.cognize(context)

        let karman = try await karmanGate.issue(
            action,
            origin: .deliberate,
            provenance: .stimulus(colored.stimulus.id)
        )
        try await effector.execute(karman)

        let bija = Bija(
            karmanRef: karman.id,
            valenceAtIssue: colored.valence,
            summary: .of(karman)
        )
        try await substrate.record(bija)
    }
}
