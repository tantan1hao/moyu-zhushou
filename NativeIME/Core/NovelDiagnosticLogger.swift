import Foundation

public enum NovelDiagnosticLogger {
    private static let queue = DispatchQueue(label: "com.tantan1hao.moyuassistant.diagnostic-log")

    public static var logFileURL: URL {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
            .appendingPathComponent(NovelIMEConstants.stateDirectoryName, isDirectory: true)
        return root.appendingPathComponent("diagnostic.log", isDirectory: false)
    }

    public static func log(_ message: String, category: String = "general") {
        let line = "[\(timestamp())] [\(category)] \(message)\n"
        queue.async {
            do {
                try ensureLogFileExists()
                let data = Data(line.utf8)
                let handle = try FileHandle(forWritingTo: logFileURL)
                defer {
                    try? handle.close()
                }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                fputs("NovelDiagnosticLogger error: \(error)\n", stderr)
            }
        }
    }

    public static func clear() {
        queue.sync {
            do {
                try ensureLogFileExists()
                try Data().write(to: logFileURL, options: .atomic)
            } catch {
                fputs("NovelDiagnosticLogger clear error: \(error)\n", stderr)
            }
        }
    }

    private static func ensureLogFileExists() throws {
        let directory = logFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }
}
