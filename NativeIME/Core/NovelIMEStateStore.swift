import Foundation
import Darwin

public final class NovelIMEStateStore: @unchecked Sendable {
    public let stateFileURL: URL
    private let lockFileURL: URL

    public init(baseDirectoryURL: URL? = nil) {
        let directoryURL = baseDirectoryURL ?? Self.defaultDirectoryURL()
        stateFileURL = directoryURL.appendingPathComponent(NovelIMEConstants.stateFileName)
        lockFileURL = directoryURL.appendingPathComponent("\(NovelIMEConstants.stateFileName).lock")
    }

    public func load() -> NovelIMEPersistedState {
        guard let data = try? Data(contentsOf: stateFileURL),
              let state = try? JSONDecoder().decode(NovelIMEPersistedState.self, from: data)
        else {
            return .default
        }
        return state
    }

    @discardableResult
    public func save(_ state: NovelIMEPersistedState) throws -> NovelIMEPersistedState {
        try withExclusiveLock {
            try write(state)
            return state
        }
    }

    @discardableResult
    public func update(_ mutate: (inout NovelIMEPersistedState) -> Void) throws -> NovelIMEPersistedState {
        try withExclusiveLock {
            var state = readStateFile() ?? .default
            mutate(&state)
            try write(state)
            return state
        }
    }

    public static func defaultDirectoryURL() -> URL {
        if let appGroupIdentifier = NovelIMEConstants.appGroupIdentifier(),
           let containerURL = FileManager.default.containerURL(
               forSecurityApplicationGroupIdentifier: appGroupIdentifier
           ) {
            return containerURL.appendingPathComponent(
                "Library/Application Support/\(NovelIMEConstants.stateDirectoryName)",
                isDirectory: true
            )
        }

        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return baseURL.appendingPathComponent(NovelIMEConstants.stateDirectoryName, isDirectory: true)
    }

    private func readStateFile() -> NovelIMEPersistedState? {
        guard let data = try? Data(contentsOf: stateFileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(NovelIMEPersistedState.self, from: data)
    }

    private func write(_ state: NovelIMEPersistedState) throws {
        let directoryURL = stateFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateFileURL, options: .atomic)
    }

    private func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        let directoryURL = stateFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let descriptor = open(lockFileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer {
            close(descriptor)
        }

        guard flock(descriptor, LOCK_EX) == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer {
            flock(descriptor, LOCK_UN)
        }

        return try operation()
    }
}
