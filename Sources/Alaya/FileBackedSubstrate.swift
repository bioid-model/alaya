import Foundation
import BioidCore

/// A `Substrate` whose `ColoredStimulus` and `Bija` history is durably
/// appended to disk as newline-delimited JSON.
///
/// `FileBackedSubstrate` is the production storehouse. Two append-only
/// NDJSON logs — `stimuli.ndjson` and `bija.ndjson` — capture every
/// `persist` and `record` call. On boot, both logs are replayed into
/// memory so that `recall` and `provideCognitionContext` can answer
/// without disk I/O.
///
/// This is the implementation that lets the BIOID claim "the substrate
/// persists across events" become operational. Restarting `alayad`
/// reloads every prior coloured stimulus and seed.
///
/// Failure modes:
/// - corrupt JSON in either log throws on init; the substrate is not
///   silently rebuilt with partial state.
/// - I/O errors during `persist` or `record` propagate; the in-memory
///   buffers are *not* updated when the on-disk write fails, so
///   recovery state matches what is actually on disk.
public actor FileBackedSubstrate: Substrate {

    private let stimulusURL: URL
    private let bijaURL: URL
    private let stimulusHandle: FileHandle
    private let bijaHandle: FileHandle
    private var stimuli: [ColoredStimulus]
    private var bija: [Bija]
    private let contextRecallLimit: Int
    private let contextBijaLimit: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var isStimulusHandleClosed: Bool = false
    private var isBijaHandleClosed: Bool = false

    public init(
        directory: URL,
        contextRecallLimit: Int = 8,
        contextBijaLimit: Int = 8
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let stimulusURL = directory.appendingPathComponent("stimuli.ndjson")
        let bijaURL = directory.appendingPathComponent("bija.ndjson")

        if !fileManager.fileExists(atPath: stimulusURL.path) {
            try Data().write(to: stimulusURL)
        }
        if !fileManager.fileExists(atPath: bijaURL.path) {
            try Data().write(to: bijaURL)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let stimuli = try Self.replay(
            url: stimulusURL,
            decoder: decoder,
            type: ColoredStimulus.self
        )
        let bija = try Self.replay(
            url: bijaURL,
            decoder: decoder,
            type: Bija.self
        )

        let stimulusHandle = try FileHandle(forWritingTo: stimulusURL)
        try stimulusHandle.seekToEnd()
        let bijaHandle = try FileHandle(forWritingTo: bijaURL)
        try bijaHandle.seekToEnd()

        self.stimulusURL = stimulusURL
        self.bijaURL = bijaURL
        self.stimulusHandle = stimulusHandle
        self.bijaHandle = bijaHandle
        self.stimuli = stimuli
        self.bija = bija
        self.contextRecallLimit = contextRecallLimit
        self.contextBijaLimit = contextBijaLimit
        self.encoder = encoder
        self.decoder = decoder
    }

    deinit {
        var firstError: (any Error)?

        if !isStimulusHandleClosed {
            do {
                try stimulusHandle.close()
                isStimulusHandleClosed = true
            } catch {
                firstError = firstError ?? error
            }
        }

        if !isBijaHandleClosed {
            do {
                try bijaHandle.close()
                isBijaHandleClosed = true
            } catch {
                firstError = firstError ?? error
            }
        }

        if let firstError {
            Self.logCloseFailure(firstError)
        }
    }

    public func persist(_ colored: ColoredStimulus) async throws {
        var line = try encoder.encode(colored)
        line.append(0x0A)
        try stimulusHandle.write(contentsOf: line)
        try stimulusHandle.synchronize()
        stimuli.append(colored)
    }

    public func record(_ bija: Bija) async throws {
        var line = try encoder.encode(bija)
        line.append(0x0A)
        try bijaHandle.write(contentsOf: line)
        try bijaHandle.synchronize()
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

    /// Close the on-disk handles. Subsequent writes will throw.
    /// Idempotent — calling close twice is a no-op.
    public func close() throws {
        try closeHandles()
    }

    private func closeHandles() throws {
        var firstError: (any Error)?

        if !isStimulusHandleClosed {
            do {
                try stimulusHandle.close()
                isStimulusHandleClosed = true
            } catch {
                firstError = firstError ?? error
            }
        }

        if !isBijaHandleClosed {
            do {
                try bijaHandle.close()
                isBijaHandleClosed = true
            } catch {
                firstError = firstError ?? error
            }
        }

        if let firstError {
            throw firstError
        }
    }

    private static func logCloseFailure(_ error: any Error) {
        let message = "FileBackedSubstrate failed to close file handles: \(error)\n"
        FileHandle.standardError.write(Data(message.utf8))
    }

    private static func replay<T: Decodable>(
        url: URL,
        decoder: JSONDecoder,
        type: T.Type
    ) throws -> [T] {
        let raw = try Data(contentsOf: url)
        var out: [T] = []
        for slice in raw.split(separator: 0x0A) where !slice.isEmpty {
            let value = try decoder.decode(T.self, from: Data(slice))
            out.append(value)
        }
        return out
    }
}
