@testable import AppBundle
import Common
import XCTest

@MainActor
final class FullscreenCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParseCenteredFlag() {
        let args = parseFullscreenArgs("fullscreen --centered")
        assertEquals(args.centered, true)

        let regularArgs = parseFullscreenArgs("fullscreen")
        assertEquals(regularArgs.centered, false)
    }

    func testParseCenteredDimensionsAndAnimation() {
        let args = parseFullscreenArgs("fullscreen --centered --width 62.5% --height 70% --animation off")
        assertEquals(args.widthPercent, 62.5)
        assertEquals(args.heightPercent, 70)
        assertEquals(args.animation, false)

        let widthOnly = parseFullscreenArgs("fullscreen --centered --width 60%")
        assertEquals(widthOnly.effectiveWidthPercent, 60)
        assertEquals(widthOnly.effectiveHeightPercent, 50)
        assertEquals(widthOnly.animation, nil)

        let heightOnly = parseFullscreenArgs("fullscreen --centered --height 80% --animation on")
        assertEquals(heightOnly.effectiveWidthPercent, 50)
        assertEquals(heightOnly.effectiveHeightPercent, 80)
        assertEquals(heightOnly.animation, true)

        let boundaryArgs = parseFullscreenArgs("fullscreen --centered --width 100% --height 0.1%")
        assertEquals(boundaryArgs.effectiveWidthPercent, 100)
        assertEquals(boundaryArgs.effectiveHeightPercent, 0.1)
    }

    func testRejectInvalidCenteredDimensionAndAnimationFlags() {
        for command in [
            "fullscreen --centered --width 60",
            "fullscreen --centered --width 0%",
            "fullscreen --centered --width -1%",
            "fullscreen --centered --height 100.1%",
            "fullscreen --centered --height nan%",
            "fullscreen --centered --height inf%",
            "fullscreen --width 60%",
            "fullscreen --height 70%",
            "fullscreen --animation off",
            "fullscreen off --animation off",
            "fullscreen --centered --animation maybe",
        ] {
            XCTAssertNotNil(parseCommand(command).errorOrNil, command)
        }
    }

    func testCenteredFullscreenUsesHalfMonitorAndPreservesTilingPeers() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let window1 = TestWindow.new(id: 1, parent: root, adaptiveWeight: 1)
        let target = TestWindow.new(id: 2, parent: root, adaptiveWeight: 2)
        let window3 = TestWindow.new(id: 3, parent: root, adaptiveWeight: 1)
        assertEquals(target.focusWindow(), true)
        try await workspace.layoutWorkspace()

        let originalTargetRect = (try await target.getAxRect(.nonCancellable)).orDie()
        let originalWindow1Rect = (try await window1.getAxRect(.nonCancellable)).orDie()
        let originalWindow3Rect = (try await window3.getAxRect(.nonCancellable)).orDie()
        let originalLayout = root.layoutDescription
        let originalHWeights = root.children.map(\.hWeight)
        let originalVWeights = root.children.map(\.vWeight)

        let result = await parseCommand("fullscreen --centered").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        try await workspace.layoutWorkspace()

        assertRectEquals(try await target.getAxRect(.nonCancellable), Rect(topLeftX: 480, topLeftY: 270, width: 960, height: 540))
        assertRectEquals(try await window1.getAxRect(.nonCancellable), originalWindow1Rect)
        assertRectEquals(try await window3.getAxRect(.nonCancellable), originalWindow3Rect)
        assertEquals(root.layoutDescription, originalLayout)
        assertEquals(root.children.map(\.hWeight), originalHWeights)
        assertEquals(root.children.map(\.vWeight), originalVWeights)
        assertEquals(target.isCenteredFullscreen, true)

        _ = await parseCommand("fullscreen --centered").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()

        assertRectEquals(try await target.getAxRect(.nonCancellable), originalTargetRect)
        assertRectEquals(try await window1.getAxRect(.nonCancellable), originalWindow1Rect)
        assertRectEquals(try await window3.getAxRect(.nonCancellable), originalWindow3Rect)
        assertEquals(root.layoutDescription, originalLayout)
        assertEquals(root.children.map(\.hWeight), originalHWeights)
        assertEquals(root.children.map(\.vWeight), originalVWeights)
        assertEquals(target.isFullscreen, false)
        assertEquals(target.isCenteredFullscreen, false)
    }

    func testCenteredDimensionsDefaultIndependentlyAndRetargetBeforeToggleExit() async throws {
        let workspace = Workspace.get(byName: name)
        let target = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(target.focusWindow(), true)
        try await workspace.layoutWorkspace()
        let originalRect = (try await target.getAxRect(.nonCancellable)).orDie()

        _ = await parseCommand("fullscreen --centered --width 60%").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertRectEquals(try await target.getAxRect(.nonCancellable), Rect(topLeftX: 384, topLeftY: 270, width: 1152, height: 540))

        _ = await parseCommand("fullscreen --centered --height 70%").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertEquals(target.isFullscreen, true)
        assertRectEquals(try await target.getAxRect(.nonCancellable), Rect(topLeftX: 480, topLeftY: 162, width: 960, height: 756))

        _ = await parseCommand("fullscreen --centered --height 70%").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertEquals(target.isFullscreen, false)
        assertRectEquals(try await target.getAxRect(.nonCancellable), originalRect)
    }

    func testCenteredOnRetargetsDifferentSizeAndFailsForIdenticalTarget() async throws {
        let workspace = Workspace.get(byName: name)
        let target = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(target.focusWindow(), true)

        _ = await parseCommand("fullscreen on --centered --width 60% --height 70%").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()

        let noop = await parseCommand("fullscreen on --centered --width 60% --height 70% --fail-if-noop").cmdOrDie
            .run(.defaultEnv, .emptyStdin)
        assertEquals(noop.exitCode.rawValue, 2)

        _ = await parseCommand("fullscreen on --centered --width 70% --height 60%").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertEquals(target.isFullscreen, true)
        assertRectEquals(try await target.getAxRect(.nonCancellable), Rect(topLeftX: 288, topLeftY: 216, width: 1344, height: 648))
    }

    func testRegularFullscreenToggleIgnoresNoOuterGapsWhenMatchingMode() async {
        let workspace = Workspace.get(byName: name)
        let target = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(target.focusWindow(), true)

        _ = await parseCommand("fullscreen on --no-outer-gaps").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(target.isFullscreen, true)

        let result = await parseCommand("fullscreen").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(target.isFullscreen, false)
    }

    func testRegularFullscreenOnFailIfNoopIgnoresNoOuterGapsWhenMatchingMode() async {
        let workspace = Workspace.get(byName: name)
        let target = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(target.focusWindow(), true)

        _ = await parseCommand("fullscreen on --no-outer-gaps").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let result = await parseCommand("fullscreen on --fail-if-noop").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(target.isFullscreen, true)
    }

    func testCenteredFullscreenPersistsAcrossPeerAndWorkspaceFocusChanges() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let target = TestWindow.new(id: 1, parent: root, adaptiveWeight: 2)
        let peer = TestWindow.new(id: 2, parent: root, adaptiveWeight: 1)
        let otherWorkspace = Workspace.get(byName: "other")
        let otherWindow = TestWindow.new(id: 3, parent: otherWorkspace.rootTilingContainer)
        assertEquals(target.focusWindow(), true)
        try await workspace.layoutWorkspace()

        let originalTargetRect = (try await target.getAxRect(.nonCancellable)).orDie()
        let originalPeerRect = (try await peer.getAxRect(.nonCancellable)).orDie()
        let originalLayout = root.layoutDescription
        let originalHWeights = root.children.map(\.hWeight)
        let originalVWeights = root.children.map(\.vWeight)
        let centeredRect = Rect(topLeftX: 384, topLeftY: 162, width: 1152, height: 756)

        _ = await parseCommand("fullscreen on --centered --width 60% --height 70%").cmdOrDie
            .run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertEquals(target.isFullscreen, true)
        assertEquals(target.isCenteredFullscreen, true)
        assertRectEquals(try await target.getAxRect(.nonCancellable), centeredRect)
        assertRectEquals(try await peer.getAxRect(.nonCancellable), originalPeerRect)

        assertEquals(peer.focusWindow(), true)
        try await workspace.layoutWorkspace()
        assertEquals(target.isFullscreen, true)
        assertEquals(target.isCenteredFullscreen, true)
        assertRectEquals(try await target.getAxRect(.nonCancellable), centeredRect)
        assertRectEquals(try await peer.getAxRect(.nonCancellable), originalPeerRect)

        assertEquals(otherWindow.focusWindow(), true)
        try await workspace.layoutWorkspace()
        assertEquals(target.isFullscreen, true)
        assertEquals(target.isCenteredFullscreen, true)
        assertRectEquals(try await target.getAxRect(.nonCancellable), centeredRect)
        assertRectEquals(try await peer.getAxRect(.nonCancellable), originalPeerRect)

        assertEquals(workspace.focusWorkspace(), true)
        assertEquals(focus.windowOrNil?.windowId, peer.windowId)
        try await workspace.layoutWorkspace()
        assertEquals(target.isFullscreen, true)
        assertEquals(target.isCenteredFullscreen, true)
        assertRectEquals(try await target.getAxRect(.nonCancellable), centeredRect)
        assertRectEquals(try await peer.getAxRect(.nonCancellable), originalPeerRect)

        assertEquals(target.focusWindow(), true)
        try await workspace.layoutWorkspace()
        assertEquals(target.isFullscreen, true)
        assertEquals(target.isCenteredFullscreen, true)
        assertRectEquals(try await target.getAxRect(.nonCancellable), centeredRect)
        assertEquals(root.layoutDescription, originalLayout)
        assertEquals(root.children.map(\.hWeight), originalHWeights)
        assertEquals(root.children.map(\.vWeight), originalVWeights)

        _ = await parseCommand("fullscreen off").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertEquals(target.isFullscreen, false)
        assertEquals(target.isCenteredFullscreen, false)
        assertRectEquals(try await target.getAxRect(.nonCancellable), originalTargetRect)
        assertRectEquals(try await peer.getAxRect(.nonCancellable), originalPeerRect)
    }

    func testRegularFullscreenExitsWhenPeerTakesFocus() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let target = TestWindow.new(id: 1, parent: root, adaptiveWeight: 2)
        let peer = TestWindow.new(id: 2, parent: root, adaptiveWeight: 1)
        assertEquals(target.focusWindow(), true)
        try await workspace.layoutWorkspace()

        let originalTargetRect = (try await target.getAxRect(.nonCancellable)).orDie()
        let originalPeerRect = (try await peer.getAxRect(.nonCancellable)).orDie()
        _ = await parseCommand("fullscreen on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertEquals(target.isFullscreen, true)
        assertRectEquals(try await target.getAxRect(.nonCancellable), Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))

        assertEquals(peer.focusWindow(), true)
        try await workspace.layoutWorkspace()
        assertEquals(target.isFullscreen, false)
        assertEquals(target.isCenteredFullscreen, false)
        assertRectEquals(try await target.getAxRect(.nonCancellable), originalTargetRect)
        assertRectEquals(try await peer.getAxRect(.nonCancellable), originalPeerRect)
    }

    func testCenteredFullscreenHitTestingUsesDisplayedRectAndLeavesVacatedTileEmpty() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let peer = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)
        TestWindow.new(id: 3, parent: root)
        assertEquals(target.focusWindow(), true)
        try await workspace.layoutWorkspace()

        let peerCenter = (try await peer.getAxRect(.nonCancellable)).orDie().center
        let targetTileCenter = (try await target.getAxRect(.nonCancellable)).orDie().center
        _ = await parseCommand("fullscreen on --centered").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        let displayedRect = (try await target.getAxRect(.nonCancellable)).orDie()

        assertEquals(
            displayedRect.center.findWindowRecursively(
                in: root,
                virtual: false,
                fullscreenCoversAll: true,
                centeredFullscreenRect: displayedRect,
            )?.windowId,
            target.windowId,
        )
        assertEquals(
            peerCenter.findWindowRecursively(
                in: root,
                virtual: false,
                fullscreenCoversAll: true,
                centeredFullscreenRect: displayedRect,
            )?.windowId,
            peer.windowId,
        )
        XCTAssertNil(
            CGPoint(x: targetTileCenter.x, y: displayedRect.topLeftY - 1).findWindowRecursively(
                in: root,
                virtual: false,
                fullscreenCoversAll: true,
                centeredFullscreenRect: displayedRect,
            ),
        )

        _ = await parseCommand("fullscreen on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            CGPoint(x: -1, y: -1).findWindowRecursively(
                in: root,
                virtual: false,
                fullscreenCoversAll: true,
                centeredFullscreenRect: nil,
            )?.windowId,
            target.windowId,
        )
    }

    func testAnimationDefaultsOffAndChangingPreferenceIsNotANoopOrAToggle() async throws {
        let workspace = Workspace.get(byName: name)
        let target = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(target.focusWindow(), true)
        try await workspace.layoutWorkspace()
        let originalRect = (try await target.getAxRect(.nonCancellable)).orDie()

        _ = await parseCommand("fullscreen on --centered --width 60%").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        let zoomedRect = (try await target.getAxRect(.nonCancellable)).orDie()

        let enable = parseCommand("fullscreen on --centered --width 60% --animation on --fail-if-noop").cmdOrDie
        let enabled = await enable.run(.defaultEnv, .emptyStdin)
        assertEquals(enabled.exitCode.rawValue, 0)
        try await workspace.layoutWorkspace()
        assertRectEquals(try await target.getAxRect(.nonCancellable), zoomedRect)
        let alreadyEnabled = await enable.run(.defaultEnv, .emptyStdin)
        assertEquals(alreadyEnabled.exitCode.rawValue, 2)

        let disable = parseCommand("fullscreen on --centered --width 60% --animation off --fail-if-noop").cmdOrDie
        let disabled = await disable.run(.defaultEnv, .emptyStdin)
        assertEquals(disabled.exitCode.rawValue, 0)
        try await workspace.layoutWorkspace()
        assertRectEquals(try await target.getAxRect(.nonCancellable), zoomedRect)
        let alreadyDisabled = await disable.run(.defaultEnv, .emptyStdin)
        assertEquals(alreadyDisabled.exitCode.rawValue, 2)

        _ = await parseCommand("fullscreen --centered --width 60% --animation on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertRectEquals(try await target.getAxRect(.nonCancellable), originalRect)
    }

    func testToggleSwitchesBetweenRegularAndCenteredFullscreen() async throws {
        let workspace = Workspace.get(byName: name)
        let target = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(target.focusWindow(), true)
        try await workspace.layoutWorkspace()
        let originalRect = (try await target.getAxRect(.nonCancellable)).orDie()

        _ = await parseCommand("fullscreen").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertRectEquals(try await target.getAxRect(.nonCancellable), Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))
        assertEquals(target.isFullscreen, true)
        assertEquals(target.isCenteredFullscreen, false)

        _ = await parseCommand("fullscreen --centered").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertRectEquals(try await target.getAxRect(.nonCancellable), Rect(topLeftX: 480, topLeftY: 270, width: 960, height: 540))
        assertEquals(target.isFullscreen, true)
        assertEquals(target.isCenteredFullscreen, true)

        _ = await parseCommand("fullscreen").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertRectEquals(try await target.getAxRect(.nonCancellable), Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))
        assertEquals(target.isFullscreen, true)
        assertEquals(target.isCenteredFullscreen, false)

        _ = await parseCommand("fullscreen off").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertRectEquals(try await target.getAxRect(.nonCancellable), originalRect)
        assertEquals(target.isFullscreen, false)
        assertEquals(target.isCenteredFullscreen, false)
    }

    func testCenteredFullscreenUsesTargetMonitorGaps() async throws {
        config.gaps = Gaps(
            inner: .zero,
            outer: .init(left: 100, bottom: 80, top: 40, right: 20),
        )
        let workspace = Workspace.get(byName: name)
        let target = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(target.focusWindow(), true)

        _ = await parseCommand("fullscreen --centered").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertRectEquals(try await target.getAxRect(.nonCancellable), Rect(topLeftX: 550, topLeftY: 280, width: 900, height: 480))

        _ = await parseCommand("fullscreen --centered --no-outer-gaps").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertRectEquals(try await target.getAxRect(.nonCancellable), Rect(topLeftX: 480, topLeftY: 270, width: 960, height: 540))
    }

    func testCenteredGeometryAccountsForMonitorOriginAndActualMinimumSize() {
        let monitorRect = Rect(topLeftX: 1440, topLeftY: 120, width: 1600, height: 900)

        assertRectEquals(
            centeredFullscreenRect(in: monitorRect, widthPercent: 62.5, heightPercent: 80),
            Rect(topLeftX: 1740, topLeftY: 210, width: 1000, height: 720),
        )
        assertRectEquals(
            centeredFullscreenRect(
                in: monitorRect,
                widthPercent: 20,
                heightPercent: 30,
                actualSize: CGSize(width: 1100, height: 600),
            ),
            Rect(topLeftX: 1690, topLeftY: 270, width: 1100, height: 600),
        )
    }
}

@MainActor
private func parseFullscreenArgs(_ raw: String) -> FullscreenCmdArgs {
    guard case .cmd(.cmd(let command)) = parseCommand(raw),
          let args = command.args as? FullscreenCmdArgs
    else { return dieT("Expected fullscreen command: \(raw)") }
    return args
}

private func assertRectEquals(
    _ actual: Rect?,
    _ expected: Rect,
    file: StaticString = #filePath,
    line: UInt = #line,
) {
    guard let actual else {
        return failExpectedActual(expected, nil, file: file, line: line)
    }
    assertEquals(actual.topLeftX, expected.topLeftX, file: file, line: line)
    assertEquals(actual.topLeftY, expected.topLeftY, file: file, line: line)
    assertEquals(actual.width, expected.width, file: file, line: line)
    assertEquals(actual.height, expected.height, file: file, line: line)
}
