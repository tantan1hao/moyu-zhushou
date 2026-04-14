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
}
