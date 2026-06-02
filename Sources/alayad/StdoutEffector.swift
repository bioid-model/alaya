import Foundation
import BioidCore

/// An `Effector` that prints `Karman.action.payload` to standard
/// output (decoded as UTF-8 when possible).
///
/// Like `StubSense`, this exists for the bootstrap composition. It is
/// not a robot driver, a network client, or a motor controller — it
/// is the smallest sink that demonstrates a `Karman` leaving the
/// substrate. Replace with a real `Effector` at the composition root.
struct StdoutEffector: Effector {

    let acceptedKinds: Set<MediaType>

    init(acceptedKinds: Set<MediaType> = [.textPlain]) {
        self.acceptedKinds = acceptedKinds
    }

    func execute(_ karman: Karman) async throws {
        guard acceptedKinds.contains(karman.action.kind) else {
            throw StdoutEffectorError.unsupportedKind(karman.action.kind)
        }
        let text = String(data: karman.action.payload, encoding: .utf8)
            ?? "<\(karman.action.payload.count) bytes>"
        print("[\(karman.action.kind)] \(text)")
    }
}

enum StdoutEffectorError: Sendable, Error, Hashable {
    case unsupportedKind(MediaType)
}
