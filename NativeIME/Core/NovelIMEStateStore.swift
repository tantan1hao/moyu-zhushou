import Foundation

public final class NovelIMEStateStore {
    public let stateFileURL: URL

    public init(baseDirectoryURL: URL? = nil) {
        let directoryURL = baseDirectoryURL ?? Self.defaultDirectoryURL()
        stateFileURL = directoryURL.appendingPathComponent(NovelIMEConstants.stateFileName)
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
        let directoryURL = stateFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateFileURL, options: .atomic)
        return state
    }

    @discardableResult
    public func update(_ mutate: (inout NovelIMEPersistedState) -> Void) throws -> NovelIMEPersistedState {
        var state = load()
        mutate(&state)
        return try save(state)
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
}
