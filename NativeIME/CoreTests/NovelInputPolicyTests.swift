import XCTest
@testable import NovelIMECore

final class NovelInputPolicyTests: XCTestCase {
    private let policy = NovelInputPolicy()

    func testAdvanceKeyInterceptsOnlyWhenArmedAndAppAllowed() {
        let action = policy.action(
            for: NovelInputKey(charactersIgnoringModifiers: "a", keyCode: 0),
            context: NovelInputContext(
                armed: true,
                frontmostBundleID: "com.microsoft.Word",
                hasRemainingText: true,
                hasPreedit: false
            )
        )

        XCTAssertEqual(action, .advancePreedit)
    }

    func testAdvanceKeyPassesThroughWhenNotArmed() {
        let action = policy.action(
            for: NovelInputKey(charactersIgnoringModifiers: "a", keyCode: 0),
            context: NovelInputContext(
                armed: false,
                frontmostBundleID: "com.microsoft.Word",
                hasRemainingText: true,
                hasPreedit: false
            )
        )

        XCTAssertEqual(action, .passThrough)
    }

    func testAdvanceKeyInterceptsInTextEditSmokeTestApp() {
        let action = policy.action(
            for: NovelInputKey(charactersIgnoringModifiers: "a", keyCode: 0),
            context: NovelInputContext(
                armed: true,
                frontmostBundleID: "com.apple.TextEdit",
                hasRemainingText: true,
                hasPreedit: false
            )
        )

        XCTAssertEqual(action, .advancePreedit)
    }

    func testAdvanceKeyPassesThroughInNonTargetApp() {
        let action = policy.action(
            for: NovelInputKey(charactersIgnoringModifiers: "a", keyCode: 0),
            context: NovelInputContext(
                armed: true,
                frontmostBundleID: "com.apple.Terminal",
                hasRemainingText: true,
                hasPreedit: false
            )
        )

        XCTAssertEqual(action, .passThrough)
    }

    func testDeleteRewindsOnlyWhenPreeditExists() {
        let delete = NovelInputKey(charactersIgnoringModifiers: nil, keyCode: 51)
        let baseContext = NovelInputContext(
            armed: true,
            frontmostBundleID: "com.microsoft.Word",
            hasRemainingText: true,
            hasPreedit: true
        )

        XCTAssertEqual(policy.action(for: delete, context: baseContext), .rewindPreedit)
        XCTAssertEqual(
            policy.action(
                for: delete,
                context: NovelInputContext(
                    armed: true,
                    frontmostBundleID: "com.microsoft.Word",
                    hasRemainingText: true,
                    hasPreedit: false
                )
            ),
            .passThrough
        )
    }

    func testReturnCommitsOnlyWhenPreeditExists() {
        let `return` = NovelInputKey(charactersIgnoringModifiers: "\r", keyCode: 36)

        XCTAssertEqual(
            policy.action(
                for: `return`,
                context: NovelInputContext(
                    armed: true,
                    frontmostBundleID: "com.kingsoft.wpsoffice.mac",
                    hasRemainingText: true,
                    hasPreedit: true
                )
            ),
            .commitPreedit
        )

        XCTAssertEqual(
            policy.action(
                for: `return`,
                context: NovelInputContext(
                    armed: true,
                    frontmostBundleID: "com.kingsoft.wpsoffice.mac",
                    hasRemainingText: true,
                    hasPreedit: false
                )
            ),
            .passThrough
        )
    }

    func testModifierShortcutsAlwaysPassThrough() {
        let action = policy.action(
            for: NovelInputKey(
                charactersIgnoringModifiers: "a",
                keyCode: 0,
                command: true
            ),
            context: NovelInputContext(
                armed: true,
                frontmostBundleID: "com.microsoft.Word",
                hasRemainingText: true,
                hasPreedit: true
            )
        )

        XCTAssertEqual(action, .passThrough)
    }

    func testOnlyAsciiLettersDigitsAndSpaceAdvance() {
        let context = NovelInputContext(
            armed: true,
            frontmostBundleID: "com.microsoft.Word",
            hasRemainingText: true,
            hasPreedit: false
        )

        XCTAssertEqual(policy.action(for: NovelInputKey(charactersIgnoringModifiers: "Z", keyCode: 6), context: context), .advancePreedit)
        XCTAssertEqual(policy.action(for: NovelInputKey(charactersIgnoringModifiers: "7", keyCode: 26), context: context), .advancePreedit)
        XCTAssertEqual(policy.action(for: NovelInputKey(charactersIgnoringModifiers: " ", keyCode: 49), context: context), .advancePreedit)
        XCTAssertEqual(policy.action(for: NovelInputKey(charactersIgnoringModifiers: "-", keyCode: 27), context: context), .passThrough)
        XCTAssertEqual(policy.action(for: NovelInputKey(charactersIgnoringModifiers: "你", keyCode: 0), context: context), .passThrough)
    }

    func testAdvanceKeyStillInterceptsWhenWaitingForCommitAtParagraphEnd() {
        let action = policy.action(
            for: NovelInputKey(charactersIgnoringModifiers: "b", keyCode: 11),
            context: NovelInputContext(
                armed: true,
                frontmostBundleID: "com.microsoft.Word",
                hasRemainingText: false,
                hasPreedit: true
            )
        )

        XCTAssertEqual(action, .advancePreedit)
    }
}
