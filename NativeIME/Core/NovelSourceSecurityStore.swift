import Foundation

public final class NovelSourceSecurityStore: @unchecked Sendable {
    public let bookmarkFileURL: URL

    public init(baseDirectoryURL: URL? = nil) {
        let directoryURL = baseDirectoryURL ?? NovelIMEStateStore.defaultDirectoryURL()
        bookmarkFileURL = directoryURL.appendingPathComponent(NovelIMEConstants.sourceBookmarkFileName)
    }

    public func saveBookmark(for sourceURL: URL) throws {
        try ensureDirectoryExists()
        let bookmarkData = try sourceURL.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try bookmarkData.write(to: bookmarkFileURL, options: .atomic)
    }

    public func clearBookmark() throws {
        guard FileManager.default.fileExists(atPath: bookmarkFileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: bookmarkFileURL)
    }

    public func resolvedSourceURL(fallback: URL? = nil) -> URL? {
        if let directURL = directlyReadableURL(from: fallback) {
            return directURL
        }

        guard let bookmarkData = try? Data(contentsOf: bookmarkFileURL) else {
            return fallback
        }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return fallback
        }

        if isStale {
            try? saveBookmark(for: resolvedURL)
        }

        return directlyReadableURL(from: resolvedURL) ?? resolvedURL
    }

    public func withAccessToSourceURL<T>(
        fallback: URL? = nil,
        _ operation: (URL) throws -> T
    ) throws -> T? {
        guard let sourceURL = resolvedSourceURL(fallback: fallback) else {
            return nil
        }

        let resolvedPath = sourceURL.standardizedFileURL.path
        let fallbackPath = fallback?.standardizedFileURL.path
        let shouldUseSecurityScope = fallbackPath == nil || fallbackPath != resolvedPath
        let securityScopeAcquired = shouldUseSecurityScope && sourceURL.startAccessingSecurityScopedResource()
        defer {
            if securityScopeAcquired {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        return try operation(sourceURL)
    }

    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: bookmarkFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func directlyReadableURL(from sourceURL: URL?) -> URL? {
        guard let sourceURL else {
            return nil
        }

        let normalizedURL = sourceURL.standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: normalizedURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: normalizedURL.path)
        else {
            return nil
        }

        return normalizedURL
    }
}
