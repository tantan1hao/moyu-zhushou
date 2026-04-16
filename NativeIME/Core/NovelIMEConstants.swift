import Foundation

public enum NovelIMEConstants {
    public static let appName = "摸鱼助手"
    public static let stateDirectoryName = "MoyuNovelIME"
    public static let stateFileName = "state.json"
    public static let sourceBookmarkFileName = "source.bookmark"
    public static let appGroupIdentifierInfoKey = "NovelIMEAppGroupIdentifier"
    public static let hostBundleIdentifier = "com.tantan1hao.inputmethod.moyuassistant"
    public static let connectionName = "\(hostBundleIdentifier)_Connection"
    public static let inputSourceIdentifier = hostBundleIdentifier
    public static let inputModeIdentifier = "com.tantan1hao.inputmethod.moyuassistant.default"
    public static let defaultAllowedBundleIDs = [
        "com.microsoft.Word",
        "com.kingsoft.wpsoffice.mac",
    ]

    public static func displayName(for bundleID: String) -> String {
        switch bundleID {
        case "com.microsoft.Word":
            return "Microsoft Word"
        case "com.kingsoft.wpsoffice.mac":
            return "WPS Writer"
        default:
            return bundleID
        }
    }

    public static func appGroupIdentifier(from bundle: Bundle = .main) -> String? {
        guard let identifier = bundle.object(forInfoDictionaryKey: appGroupIdentifierInfoKey) as? String,
              !identifier.isEmpty,
              !identifier.contains("$(")
        else {
            return nil
        }
        return identifier
    }
}
