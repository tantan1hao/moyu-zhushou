import Foundation

public struct NovelIMEPersistedState: Codable, Equatable, Sendable {
    public var sourceFileURL: String?
    public var armed: Bool
    public var allowedBundleIDs: [String]
    public var paragraphIndex: Int
    public var charIndex: Int
    public var eofReached: Bool

    public init(
        sourceFileURL: String? = nil,
        armed: Bool = false,
        allowedBundleIDs: [String] = NovelIMEConstants.defaultAllowedBundleIDs,
        paragraphIndex: Int = 0,
        charIndex: Int = 0,
        eofReached: Bool = false
    ) {
        self.sourceFileURL = sourceFileURL
        self.armed = armed
        self.allowedBundleIDs = allowedBundleIDs
        self.paragraphIndex = paragraphIndex
        self.charIndex = charIndex
        self.eofReached = eofReached
    }

    public static let `default` = NovelIMEPersistedState()

    public var resolvedSourceURL: URL? {
        guard let sourceFileURL, !sourceFileURL.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: sourceFileURL)
    }
}

public struct ProgressSnapshot: Equatable, Sendable {
    public let paragraphIndex: Int
    public let paragraphCount: Int
    public let charIndex: Int
    public let currentParagraphLength: Int
    public let progress: Double
    public let preeditBuffer: String
    public let eofReached: Bool

    public var formattedProgress: String {
        guard paragraphCount > 0 else {
            return "未开始"
        }

        let paragraphNumber = min(paragraphIndex + 1, paragraphCount)
        return String(
            format: "段 %d/%d 字 %d/%d (%.1f%%)",
            paragraphNumber,
            paragraphCount,
            charIndex,
            currentParagraphLength,
            progress * 100
        )
    }
}
