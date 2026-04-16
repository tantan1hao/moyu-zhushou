import XCTest
@testable import NovelIMECore

final class NovelPlaybackEngineTests: XCTestCase {
    private let loader = NovelDocumentLoader()

    func testNormalizeParagraphsAndWhitespace() throws {
        let paragraphs = loader.normalizeParagraphs(
            "  第一段\t  有  多余空白  \n\n第二段\r\n  仍然   会  归一化  \n\n\n  第三段  "
        )

        XCTAssertEqual(
            paragraphs,
            ["第一段 有 多余空白", "第二段 仍然 会 归一化", "第三段"]
        )
    }

    func testAppendNextCharacterBuildsPreedit() throws {
        let document = NovelDocument(sourceURL: URL(fileURLWithPath: "/tmp/sample.txt"), paragraphs: ["AB", "CD"])
        let engine = NovelPlaybackEngine(document: document, state: .default)

        XCTAssertEqual(engine.appendNextCharacter(), "A")
        XCTAssertEqual(engine.appendNextCharacter(), "B")
        XCTAssertEqual(engine.preeditBuffer, "AB")
        XCTAssertNil(engine.appendNextCharacter())
        XCTAssertEqual(engine.progressSnapshot().formattedProgress, "段 1/2 字 2/2 (40.0%)")
    }

    func testCommitAtParagraphEndMovesToNextParagraphAndPreservesNewline() {
        let document = NovelDocument(sourceURL: URL(fileURLWithPath: "/tmp/sample.txt"), paragraphs: ["AB", "CD"])
        let engine = NovelPlaybackEngine(document: document, state: .default)

        _ = engine.appendNextCharacter()
        _ = engine.appendNextCharacter()
        let result = engine.commitPreedit()

        XCTAssertEqual(result.text, "AB\n")
        XCTAssertTrue(result.advancedParagraph)
        XCTAssertEqual(engine.committedParagraphIndex, 1)
        XCTAssertEqual(engine.committedCharIndex, 0)
        XCTAssertEqual(engine.progressSnapshot().formattedProgress, "段 2/2 字 0/2 (60.0%)")
    }

    func testCommitInsideParagraphDoesNotAdvanceParagraph() {
        let document = NovelDocument(sourceURL: URL(fileURLWithPath: "/tmp/sample.txt"), paragraphs: ["ABCD", "EF"])
        let engine = NovelPlaybackEngine(document: document, state: .default)

        _ = engine.appendNextCharacter()
        _ = engine.appendNextCharacter()
        let result = engine.commitPreedit()

        XCTAssertEqual(result.text, "AB")
        XCTAssertFalse(result.advancedParagraph)
        XCTAssertFalse(result.eofReached)
        XCTAssertEqual(engine.committedParagraphIndex, 0)
        XCTAssertEqual(engine.committedCharIndex, 2)
        XCTAssertEqual(engine.progressSnapshot().formattedProgress, "段 1/2 字 2/4 (28.6%)")
    }

    func testRewindPreeditRestoresCurrentCursorWithoutPersisting() {
        let document = NovelDocument(sourceURL: URL(fileURLWithPath: "/tmp/sample.txt"), paragraphs: ["AB"])
        let engine = NovelPlaybackEngine(document: document, state: .default)

        _ = engine.appendNextCharacter()
        _ = engine.appendNextCharacter()
        XCTAssertEqual(engine.rewindPreedit(), "B")
        XCTAssertEqual(engine.preeditBuffer, "A")
        XCTAssertEqual(engine.committedCharIndex, 0)
        XCTAssertEqual(engine.progressSnapshot().charIndex, 1)
    }

    func testClearPreeditRestoresCommittedCursor() {
        let document = NovelDocument(sourceURL: URL(fileURLWithPath: "/tmp/sample.txt"), paragraphs: ["ABCD"])
        let state = NovelIMEPersistedState(paragraphIndex: 0, charIndex: 1)
        let engine = NovelPlaybackEngine(document: document, state: state)

        _ = engine.appendNextCharacter()
        _ = engine.appendNextCharacter()
        engine.clearPreedit()

        XCTAssertEqual(engine.preeditBuffer, "")
        XCTAssertEqual(engine.paragraphIndex, 0)
        XCTAssertEqual(engine.charIndex, 1)
        XCTAssertEqual(engine.committedCharIndex, 1)
    }

    func testCommitLastParagraphMarksEOF() {
        let document = NovelDocument(sourceURL: URL(fileURLWithPath: "/tmp/sample.txt"), paragraphs: ["AB"])
        let engine = NovelPlaybackEngine(document: document, state: .default)

        _ = engine.appendNextCharacter()
        _ = engine.appendNextCharacter()
        let result = engine.commitPreedit()
        let persisted = engine.persistedState(from: .default)

        XCTAssertEqual(result.text, "AB")
        XCTAssertFalse(result.advancedParagraph)
        XCTAssertTrue(result.eofReached)
        XCTAssertTrue(engine.eofReached)
        XCTAssertFalse(engine.hasRemainingText)
        XCTAssertEqual(persisted.paragraphIndex, 0)
        XCTAssertEqual(persisted.charIndex, 2)
        XCTAssertTrue(persisted.eofReached)
    }

    func testEmptyDocumentStartsAtEOF() {
        let document = NovelDocument(sourceURL: URL(fileURLWithPath: "/tmp/sample.txt"), paragraphs: [])
        let engine = NovelPlaybackEngine(document: document, state: .default)

        XCTAssertFalse(engine.hasRemainingText)
        XCTAssertTrue(engine.eofReached)
        XCTAssertEqual(engine.progressSnapshot().formattedProgress, "未开始")
        XCTAssertNil(engine.appendNextCharacter())
    }

    func testLoadSourceConvertsRTFDisguisedAsText() throws {
        let rtfText = "{\\rtf1\\ansi\\ansicpg936\\cocoartf2822 \\uc0\\u25105 \\u29233 \\u20320 }"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try rtfText.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try loader.load(from: url)

        XCTAssertEqual(document.paragraphs, ["我爱你"])
    }

    func testLoadSourceConvertsRTFWithLeadingBOM() throws {
        let rtfText = "\u{feff}   {\\rtf1\\ansi hello}"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try rtfText.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try loader.load(from: url)

        XCTAssertEqual(document.paragraphs, ["hello"])
    }

    func testLoadSourceDecodesUTF16Text() throws {
        let text = "第一段\n\n第二段"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try text.write(to: url, atomically: true, encoding: .utf16)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try loader.load(from: url)

        XCTAssertEqual(document.paragraphs, ["第一段", "第二段"])
    }
}
