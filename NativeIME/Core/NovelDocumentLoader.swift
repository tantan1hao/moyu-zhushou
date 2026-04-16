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

public struct NovelDocumentLoader: Sendable {
    public init() {}

    public func load(from sourceURL: URL) throws -> NovelDocument {
        let data = try Data(contentsOf: sourceURL)
        let decodedText = try decodeText(from: data, sourceURL: sourceURL)
        return NovelDocument(sourceURL: sourceURL, paragraphs: normalizeParagraphs(decodedText))
    }

    public func decodeText(from data: Data, sourceURL: URL) throws -> String {
        if let detectedRTF = decodeRTFIfNeeded(from: data) {
            return detectedRTF
        }

        for encoding in candidateEncodings {
            if let decodedText = String(data: data, encoding: encoding), !decodedText.isEmpty {
                return decodedText
            }
        }

        let lossyText = String(decoding: data, as: UTF8.self)
        if let converted = decodeRTFIfNeeded(from: data, fallbackText: lossyText) {
            return converted
        }

        guard !lossyText.isEmpty || !data.isEmpty else {
            throw NovelDocumentLoaderError.unreadableSource(sourceURL)
        }
        return lossyText
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

    private var candidateEncodings: [String.Encoding] {
        [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .utf32,
            .utf32LittleEndian,
            .utf32BigEndian,
            .unicode,
            String.Encoding(
                rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            ),
        ]
    }

    private func decodeRTFIfNeeded(from data: Data, fallbackText: String? = nil) -> String? {
        let fallbackText = fallbackText ?? String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        guard looksLikeRTF(fallbackText) else {
            return nil
        }
        if let converted = convertRTFToPlainText(data) {
            return converted
        }

        let sanitizedRTF = fallbackText
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}"))
            )
        guard let sanitizedData = sanitizedRTF.data(using: .utf8) else {
            return nil
        }
        return convertRTFToPlainText(sanitizedData)
    }

    private func looksLikeRTF(_ text: String) -> Bool {
        text
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}"))
            )
            .hasPrefix("{\\rtf")
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
