import XCTest
@testable import NovelIMECore

final class NovelIMEStateStoreTests: XCTestCase {
    func testStateStoreRoundTripsPersistedState() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = NovelIMEStateStore(baseDirectoryURL: tempURL)
        let state = NovelIMEPersistedState(
            sourceFileURL: "/tmp/source.txt",
            armed: true,
            allowedBundleIDs: ["com.microsoft.Word"],
            paragraphIndex: 2,
            charIndex: 10,
            eofReached: false
        )

        try store.save(state)

        XCTAssertEqual(store.load(), state)
    }

    func testUpdatePreservesUnchangedFields() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = NovelIMEStateStore(baseDirectoryURL: tempURL)
        let initialState = NovelIMEPersistedState(
            sourceFileURL: "/tmp/source.txt",
            armed: true,
            allowedBundleIDs: ["com.microsoft.Word", "com.kingsoft.wpsoffice.mac"],
            paragraphIndex: 1,
            charIndex: 8,
            eofReached: false
        )

        try store.save(initialState)
        let updatedState = try store.update { state in
            state.paragraphIndex = 3
            state.charIndex = 2
            state.eofReached = true
        }

        XCTAssertEqual(updatedState.sourceFileURL, initialState.sourceFileURL)
        XCTAssertEqual(updatedState.armed, initialState.armed)
        XCTAssertEqual(updatedState.allowedBundleIDs, initialState.allowedBundleIDs)
        XCTAssertEqual(updatedState.paragraphIndex, 3)
        XCTAssertEqual(updatedState.charIndex, 2)
        XCTAssertTrue(updatedState.eofReached)
    }

    func testSecurityStorePrefersDirectReadableFallbackOverBookmark() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)

        let fallbackURL = tempURL.appendingPathComponent("source.txt")
        try "hello".write(to: fallbackURL, atomically: true, encoding: .utf8)

        let securityStore = NovelSourceSecurityStore(baseDirectoryURL: tempURL)
        try Data("not-a-bookmark".utf8).write(to: securityStore.bookmarkFileURL, options: .atomic)

        XCTAssertEqual(securityStore.resolvedSourceURL(fallback: fallbackURL), fallbackURL.standardizedFileURL)

        let loadedText = try securityStore.withAccessToSourceURL(fallback: fallbackURL) { url in
            try String(contentsOf: url, encoding: .utf8)
        }
        XCTAssertEqual(loadedText, "hello")
    }
}
