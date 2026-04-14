import Foundation

public struct CommitResult: Equatable, Sendable {
    public let text: String
    public let advancedParagraph: Bool
    public let eofReached: Bool
}

public final class NovelPlaybackEngine {
    public let document: NovelDocument
    public private(set) var committedParagraphIndex: Int
    public private(set) var committedCharIndex: Int
    public private(set) var paragraphIndex: Int
    public private(set) var charIndex: Int
    public private(set) var preeditBuffer: String

    public init(document: NovelDocument, state: NovelIMEPersistedState) {
        self.document = document

        let clampedCursor = Self.clampCursor(
            paragraphIndex: state.paragraphIndex,
            charIndex: state.charIndex,
            in: document
        )

        committedParagraphIndex = clampedCursor.paragraphIndex
        committedCharIndex = clampedCursor.charIndex
        paragraphIndex = clampedCursor.paragraphIndex
        charIndex = clampedCursor.charIndex
        preeditBuffer = ""
    }

    public var paragraphCount: Int {
        document.paragraphCount
    }

    public var hasRemainingText: Bool {
        guard paragraphCount > 0 else {
            return false
        }
        if paragraphIndex < paragraphCount - 1 {
            return true
        }
        return charIndex < paragraphLength(at: paragraphIndex)
    }

    public var eofReached: Bool {
        guard paragraphCount > 0 else {
            return true
        }
        let lastParagraphIndex = paragraphCount - 1
        return committedParagraphIndex == lastParagraphIndex
            && committedCharIndex >= paragraphLength(at: lastParagraphIndex)
            && preeditBuffer.isEmpty
    }

    public func appendNextCharacter() -> String? {
        guard let nextCharacter = currentCharacter() else {
            return nil
        }

        preeditBuffer.append(nextCharacter)
        charIndex += 1
        return String(nextCharacter)
    }

    @discardableResult
    public func rewindPreedit() -> String? {
        guard !preeditBuffer.isEmpty, charIndex > committedCharIndex else {
            return nil
        }

        let removed = preeditBuffer.removeLast()
        charIndex -= 1
        return String(removed)
    }

    public func clearPreedit() {
        preeditBuffer.removeAll()
        paragraphIndex = committedParagraphIndex
        charIndex = committedCharIndex
    }

    public func commitPreedit() -> CommitResult {
        guard !preeditBuffer.isEmpty else {
            return CommitResult(text: "", advancedParagraph: false, eofReached: eofReached)
        }

        let shouldAdvanceParagraph = isAtParagraphEnd && paragraphIndex < paragraphCount - 1
        var committedText = preeditBuffer
        if shouldAdvanceParagraph {
            committedText.append("\n")
        }

        if shouldAdvanceParagraph {
            committedParagraphIndex = paragraphIndex + 1
            committedCharIndex = 0
        } else {
            committedParagraphIndex = paragraphIndex
            committedCharIndex = charIndex
        }

        paragraphIndex = committedParagraphIndex
        charIndex = committedCharIndex
        preeditBuffer.removeAll()

        return CommitResult(
            text: committedText,
            advancedParagraph: shouldAdvanceParagraph,
            eofReached: eofReached
        )
    }

    public func progressSnapshot() -> ProgressSnapshot {
        let currentParagraphLength = paragraphLength(at: paragraphIndex)
        return ProgressSnapshot(
            paragraphIndex: paragraphIndex,
            paragraphCount: paragraphCount,
            charIndex: charIndex,
            currentParagraphLength: currentParagraphLength,
            progress: computeProgress(),
            preeditBuffer: preeditBuffer,
            eofReached: eofReached
        )
    }

    public func persistedState(from existing: NovelIMEPersistedState) -> NovelIMEPersistedState {
        NovelIMEPersistedState(
            sourceFileURL: existing.sourceFileURL,
            armed: existing.armed,
            allowedBundleIDs: existing.allowedBundleIDs,
            paragraphIndex: committedParagraphIndex,
            charIndex: committedCharIndex,
            eofReached: eofReached
        )
    }

    private var isAtParagraphEnd: Bool {
        guard paragraphIndex < paragraphCount else {
            return true
        }
        return charIndex >= paragraphLength(at: paragraphIndex)
    }

    private func currentCharacter() -> Character? {
        guard paragraphIndex >= 0, paragraphIndex < paragraphCount else {
            return nil
        }
        let characters = Array(document.paragraphs[paragraphIndex])
        guard charIndex >= 0, charIndex < characters.count else {
            return nil
        }
        return characters[charIndex]
    }

    private func paragraphLength(at index: Int) -> Int {
        guard index >= 0, index < paragraphCount else {
            return 0
        }
        return document.paragraphs[index].count
    }

    private func computeProgress() -> Double {
        let totalUnits = totalUnitCount
        guard totalUnits > 0 else {
            return 1
        }
        return Double(flatPosition(paragraphIndex: paragraphIndex, charIndex: charIndex)) / Double(totalUnits)
    }

    private var totalUnitCount: Int {
        guard paragraphCount > 0 else {
            return 0
        }
        let paragraphCharacters = document.paragraphs.reduce(0) { $0 + $1.count }
        let separatorCount = max(paragraphCount - 1, 0)
        return paragraphCharacters + separatorCount
    }

    private func flatPosition(paragraphIndex: Int, charIndex: Int) -> Int {
        guard paragraphCount > 0 else {
            return 0
        }

        var position = 0
        let cappedParagraphIndex = min(max(paragraphIndex, 0), paragraphCount - 1)
        for index in 0..<cappedParagraphIndex {
            position += document.paragraphs[index].count + 1
        }
        position += min(charIndex, paragraphLength(at: cappedParagraphIndex))
        return position
    }

    private static func clampCursor(
        paragraphIndex: Int,
        charIndex: Int,
        in document: NovelDocument
    ) -> (paragraphIndex: Int, charIndex: Int) {
        guard document.paragraphCount > 0 else {
            return (0, 0)
        }

        let clampedParagraphIndex = min(max(paragraphIndex, 0), document.paragraphCount - 1)
        let paragraphLength = document.paragraphs[clampedParagraphIndex].count
        let clampedCharIndex = min(max(charIndex, 0), paragraphLength)
        return (clampedParagraphIndex, clampedCharIndex)
    }
}
