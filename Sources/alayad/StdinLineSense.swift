import Foundation
import BioidCore

/// A `Sense` that turns each line of standard input into a
/// `MediaType.textPlain` `Stimulus`.
///
/// `StdinLineSense` is the first real `Sense` conformer in the BIOID
/// repository. It reads `FileHandle.standardInput.bytes.lines` in a
/// detached task and yields one `Stimulus` per line until the stream
/// reaches EOF or `shutdown()` is called.
///
/// Lifetime:
/// - the detached reader task starts when `stimuli()` is called.
/// - the stream finishes naturally on EOF (Ctrl-D from a tty).
/// - `shutdown()` finishes the stream and cancels the reader task —
///   any `for await` loop downstream terminates at the next boundary.
final class StdinLineSense: Sense {

    let emittedMediaTypes: Set<MediaType> = [.textPlain]

    private let state = State()

    private actor State {
        var continuation: AsyncThrowingStream<Stimulus, Error>.Continuation?
        var task: Task<Void, Never>?
        var isShutDown: Bool = false

        func attach(
            continuation: AsyncThrowingStream<Stimulus, Error>.Continuation,
            task: Task<Void, Never>
        ) {
            if isShutDown {
                continuation.finish()
                task.cancel()
                return
            }
            self.continuation = continuation
            self.task = task
        }

        func finishIfNeeded() {
            guard !isShutDown else { return }
            isShutDown = true
            continuation?.finish()
            task?.cancel()
            continuation = nil
            task = nil
        }
    }

    init() {}

    func stimuli() -> AsyncThrowingStream<Stimulus, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                let stdin = FileHandle.standardInput
                do {
                    for try await line in stdin.bytes.lines {
                        try Task.checkCancellation()
                        let trimmed = line
                        let stim = Stimulus(
                            mediaType: .textPlain,
                            data: Data(trimmed.utf8)
                        )
                        continuation.yield(stim)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            let state = self.state
            Task {
                await state.attach(continuation: continuation, task: task)
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func shutdown() async {
        await state.finishIfNeeded()
    }
}
