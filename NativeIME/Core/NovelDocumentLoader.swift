import AppKit
import Foundation

public struct NovelDocument: Equatable, Sendable {
    public let sourceURL: URL
    public let paragraphs: [String]

    public var paragraphCount: Int {
        paragraphs.count
    }
}

public enum NovelDocumentLoaderError: LocalizedError {
    case unreadableSource(URL)

    public var errorDescription: String? {
        switch self {
        case let .unreadableSource(url):
            return "无法读取稿源文件：\(url.path)"
        }
    }
}

public struct NovelDocumentLoader {
    public init() {}

    public func load(from sourceURL: URL) throws -> NovelDocument {
        let data = try Data(contentsOf: sourceURL)
        let decodedText = try decodeText(from: data, sourceURL: sourceURL)
        return NovelDocument(sourceURL: sourceURL, paragraphs: normalizeParagraphs(decodedText))
    }

    public func decodeText(from data: Data, sourceURL: URL) throws -> String {
        let rawText = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        if looksLikeRTF(rawText), let converted = convertRTFToPlainText(data) {
            return converted
        }
        guard !rawText.isEmpty || !data.isEmpty else {
            throw NovelDocumentLoaderError.unreadableSource(sourceURL)
        }
        return rawText
    }

    public func normalizeParagraphs(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var paragraphs: [String] = []
        var currentLines: [String] = []

        func flushParagraph() {
            guard !currentLines.isEmpty else {
                return
            }

            let merged = currentLines.joined(separator: " ")
            let collapsed = merged.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !collapsed.isEmpty {
                paragraphs.append(collapsed)
            }
            currentLines.removeAll(keepingCapacity: true)
        }

        for line in normalized.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flushParagraph()
            } else {
                currentLines.append(line)
            }
        }

        flushParagraph()
        return paragraphs
    }

    private func looksLikeRTF(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{\\rtf")
    }

    private func convertRTFToPlainText(_ data: Data) -> String? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf,
        ]
        guard let attributed = try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        ) else {
            return nil
        }
        return attributed.string
    }
}
