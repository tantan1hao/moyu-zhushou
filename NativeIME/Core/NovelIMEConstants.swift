import Foundation

public enum NovelIMEConstants {
    public static let appName = "摸鱼助手"
    public static let stateDirectoryName = "MoyuNovelIME"
    public static let stateFileName = "state.json"
    public static let hostBundleIdentifier = "com.tantan1hao.moyuassistant"
    public static let extensionBundleIdentifier = "com.tantan1hao.moyuassistant.inputmethod"
    public static let connectionName = "com.tantan1hao.moyuassistant.connection"
    public static let inputSourceIdentifier = "com.tantan1hao.moyuassistant.source"
    public static let inputModeIdentifier = "com.tantan1hao.moyuassistant.mode.default"
    public static let defaultAllowedBundleIDs = [
        "com.apple.TextEdit",
        "com.microsoft.Word",
        "com.kingsoft.wpsoffice.mac",
    ]

    public static func displayName(for bundleID: String) -> String {
        switch bundleID {
        case "com.apple.TextEdit":
            return "TextEdit"
        case "com.microsoft.Word":
            return "Microsoft Word"
        case "com.kingsoft.wpsoffice.mac":
            return "WPS Writer"
        default:
            return bundleID
        }
    }
}
