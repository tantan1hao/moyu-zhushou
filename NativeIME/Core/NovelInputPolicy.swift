import Foundation

public enum NovelInputAction: Equatable, Sendable {
    case advancePreedit
    case rewindPreedit
    case commitPreedit
    case passThrough
}

public struct NovelInputKey: Equatable, Sendable {
    public let charactersIgnoringModifiers: String?
    public let keyCode: UInt16
    public let command: Bool
    public let control: Bool
    public let option: Bool

    public init(
        charactersIgnoringModifiers: String?,
        keyCode: UInt16,
        command: Bool = false,
        control: Bool = false,
        option: Bool = false
    ) {
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.keyCode = keyCode
        self.command = command
        self.control = control
        self.option = option
    }
}

public struct NovelInputContext: Equatable, Sendable {
    public let armed: Bool
    public let frontmostBundleID: String
    public let allowedBundleIDs: [String]
    public let hasRemainingText: Bool
    public let hasPreedit: Bool

    public init(
        armed: Bool,
        frontmostBundleID: String,
        allowedBundleIDs: [String] = NovelIMEConstants.defaultAllowedBundleIDs,
        hasRemainingText: Bool,
        hasPreedit: Bool
    ) {
        self.armed = armed
        self.frontmostBundleID = frontmostBundleID
        self.allowedBundleIDs = allowedBundleIDs
        self.hasRemainingText = hasRemainingText
        self.hasPreedit = hasPreedit
    }
}

public struct NovelInputPolicy: Sendable {
    public init() {}

    public func action(for key: NovelInputKey, context: NovelInputContext) -> NovelInputAction {
        guard !key.command, !key.control, !key.option else {
            return .passThrough
        }

        guard context.armed else {
            return .passThrough
        }

        guard context.allowedBundleIDs.contains(context.frontmostBundleID) else {
            return .passThrough
        }

        if isDelete(key) {
            return context.hasPreedit ? .rewindPreedit : .passThrough
        }

        if isReturn(key) {
            return context.hasPreedit ? .commitPreedit : .passThrough
        }

        if isAdvanceKey(key) {
            return context.hasRemainingText || context.hasPreedit ? .advancePreedit : .passThrough
        }

        return .passThrough
    }

    private func isAdvanceKey(_ key: NovelInputKey) -> Bool {
        guard let characters = key.charactersIgnoringModifiers, characters.count == 1 else {
            return false
        }

        guard let ascii = characters.utf8.first else {
            return false
        }

        return characters == " "
            || (ascii >= CharacterCode.zero && ascii <= CharacterCode.nine)
            || (ascii >= CharacterCode.uppercaseA && ascii <= CharacterCode.uppercaseZ)
            || (ascii >= CharacterCode.lowercaseA && ascii <= CharacterCode.lowercaseZ)
    }

    private func isDelete(_ key: NovelInputKey) -> Bool {
        key.keyCode == KeyCode.delete
    }

    private func isReturn(_ key: NovelInputKey) -> Bool {
        key.keyCode == KeyCode.return || key.keyCode == KeyCode.keypadReturn
    }
}

private enum KeyCode {
    static let `return`: UInt16 = 36
    static let delete: UInt16 = 51
    static let keypadReturn: UInt16 = 76
}

private enum CharacterCode {
    static let zero = UInt8(ascii: "0")
    static let nine = UInt8(ascii: "9")
    static let uppercaseA = UInt8(ascii: "A")
    static let uppercaseZ = UInt8(ascii: "Z")
    static let lowercaseA = UInt8(ascii: "a")
    static let lowercaseZ = UInt8(ascii: "z")
}
