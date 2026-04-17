import Foundation

public enum NovelDiagnosticLogger {
    private static let queue = DispatchQueue(label: "com.tantan1hao.moyuassistant.logging")

    public static var logFileURL: URL {
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
            .appendingPathComponent(NovelIMEConstants.stateDirectoryName, isDirectory: true)
        return logsDirectory.appendingPathComponent("diagnostic.log", isDirectory: false)
    }

    public static func log(
        _ category: String,
        _ message: @autoclosure @escaping () -> String,
        function: String = #function
    ) {
        let renderedMessage = message()
        queue.async {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] [\(category)] [\(function)] \(renderedMessage)\n"
            let fileURL = logFileURL

            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                if FileManager.default.fileExists(atPath: fileURL.path) == false {
                    try Data().write(to: fileURL, options: .atomic)
                }

                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
                fputs("NovelDiagnosticLogger write failed: \(error)\n", stderr)
            }
        }
    }

    public static func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: logFileURL)
        }
    }
}
