import AppKit
import Common

open class Window: TreeNode, Hashable {
    let windowId: UInt32
    let app: any AbstractApp
    var lastFloatingSize: CGSize?
    var isFullscreen: Bool = false
    var noOuterGapsInFullscreen: Bool = false
    var isCenteredFullscreen: Bool = false
    var shouldAnimateNextLayoutFromCentered: Bool = false
    var centeredFullscreenWidthPercent: CGFloat = 50
    var centeredFullscreenHeightPercent: CGFloat = 50
    var centeredFullscreenAnimationEnabled: Bool = false
    @MainActor private var centeredFullscreenTransitionTask: Task<Void, Never>?
    @MainActor private var centeredFullscreenTransitionTarget: Rect?
    @MainActor private var centeredFullscreenTransitionGeneration: UInt = 0
    var layoutReason: LayoutReason = .standard

    @MainActor
    init(id: UInt32, _ app: any AbstractApp, lastFloatingSize: CGSize?, parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) {
        self.windowId = id
        self.app = app
        self.lastFloatingSize = lastFloatingSize
        super.init(parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    @MainActor static func get(byId windowId: UInt32) -> Window? { // todo make non optional
        isUnitTest
            ? Workspace.all.flatMap { $0.allLeafWindowsRecursive }.first(where: { $0.windowId == windowId })
            : MacWindow.allWindowsMap[windowId]
    }

    @MainActor
    func closeAxWindow() { die("Not implemented") }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(windowId)
    }

    func getAxSize(_ cm: CancellationMode) async throws -> CGSize? { die("Not implemented") }
    func getTitle(_ cm: CancellationMode) async throws -> String { die("Not implemented") }
    func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool { false }
    func isMacosMinimized(_ cm: CancellationMode) async throws -> Bool { false } // todo replace with enum MacOsWindowNativeState { normal, fullscreen, invisible }
    var isHiddenInCorner: Bool { die("Not implemented") }
    @MainActor func nativeFocus() { die("Not implemented") }
    func getAxRect(_ cm: CancellationMode) async throws -> Rect? { die("Not implemented") }
    func getCenter(_ cm: CancellationMode) async throws -> CGPoint? { try await getAxRect(cm)?.center }

    func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) { die("Not implemented") }
    func setAxFrameCentered(_ requestedRect: Rect, in monitorRect: Rect) {
        setAxFrame(requestedRect.topLeftCorner, requestedRect.size)
    }
    func cancelPendingAxFrame() {}
}
extension Window {

    @MainActor
    func cancelCenteredFullscreenTransition() {
        centeredFullscreenTransitionGeneration &+= 1
        centeredFullscreenTransitionTask?.cancel()
        centeredFullscreenTransitionTask = nil
        cancelPendingAxFrame()
        centeredFullscreenTransitionTarget = nil
    }

    @MainActor
    func applyLayoutFrame(_ target: Rect, animateFromCentered: Bool, centeredIn monitorRect: Rect? = nil) {
        if let transitionTarget = centeredFullscreenTransitionTarget,
           transitionTarget.isApproximatelyEqual(to: target),
           centeredFullscreenTransitionTask != nil
        {
            return
        }

        cancelCenteredFullscreenTransition()
        if isUnitTest || !animateFromCentered || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            applyFinalLayoutFrame(target, centeredIn: monitorRect)
            return
        }

        centeredFullscreenTransitionTarget = target
        centeredFullscreenTransitionGeneration &+= 1
        let generation = centeredFullscreenTransitionGeneration
        centeredFullscreenTransitionTask = Task.startUnstructured { @MainActor [weak self] in
            guard let self else { return }
            let initial = try? await getAxRect(.cancellable)
            guard generation == centeredFullscreenTransitionGeneration, !Task.isCancelled else { return }
            guard isCenteredFullscreenTransitionEligible else {
                cancelCenteredFullscreenTransition()
                return
            }
            guard let initial else {
                applyFinalLayoutFrame(target, centeredIn: monitorRect)
                finishCenteredFullscreenTransition(generation)
                return
            }

            do {
                let frameCount = 12
                for frame in 1 ... frameCount {
                    try await Task.sleep(for: .milliseconds(200 / frameCount))
                    try Task.checkCancellation()
                    guard generation == centeredFullscreenTransitionGeneration else { return }
                    guard isCenteredFullscreenTransitionEligible else {
                        cancelCenteredFullscreenTransition()
                        return
                    }
                    let progress = CGFloat(frame) / CGFloat(frameCount)
                    let easedProgress = 1 - pow(1 - progress, 3)
                    let frameRect = initial.interpolated(to: target, progress: easedProgress)
                    if frame == frameCount {
                        applyFinalLayoutFrame(frameRect, centeredIn: monitorRect)
                    } else {
                        setAxFrame(frameRect.topLeftCorner, frameRect.size)
                    }
                }
                finishCenteredFullscreenTransition(generation)
            } catch is CancellationError {
                // A newer layout target owns the window now.
            } catch {
                die("Unexpected centered fullscreen transition error: \(error)")
            }
        }
    }

    @MainActor
    private var isCenteredFullscreenTransitionEligible: Bool {
        guard currentlyManipulatedWithMouseWindowId != windowId, nodeWorkspace?.isVisible == true else { return false }
        return switch windowParentCases {
            case .tilingContainer, .floatingWindowsContainer: true
            case .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer,
                 .macosMinimizedWindowsContainer, .macosPopupWindowsContainer, .unbound: false
        }
    }

    @MainActor
    private func finishCenteredFullscreenTransition(_ generation: UInt) {
        if generation == centeredFullscreenTransitionGeneration {
            centeredFullscreenTransitionTask = nil
            centeredFullscreenTransitionTarget = nil
        }
    }

    @MainActor
    private func applyFinalLayoutFrame(_ target: Rect, centeredIn monitorRect: Rect?) {
        if let monitorRect {
            setAxFrameCentered(target, in: monitorRect)
        } else {
            setAxFrame(target.topLeftCorner, target.size)
        }
    }
}

func centeredFullscreenRect(
    in monitorRect: Rect,
    widthPercent: CGFloat = 50,
    heightPercent: CGFloat = 50,
    actualSize: CGSize? = nil,
) -> Rect {
    let size = actualSize ?? CGSize(
        width: monitorRect.width * widthPercent / 100,
        height: monitorRect.height * heightPercent / 100,
    )
    return Rect(
        topLeftX: monitorRect.center.x - size.width / 2,
        topLeftY: monitorRect.center.y - size.height / 2,
        width: size.width,
        height: size.height,
    )
}

extension Rect {
    fileprivate func interpolated(to target: Rect, progress: CGFloat) -> Rect {
        Rect(
            topLeftX: topLeftX + (target.topLeftX - topLeftX) * progress,
            topLeftY: topLeftY + (target.topLeftY - topLeftY) * progress,
            width: width + (target.width - width) * progress,
            height: height + (target.height - height) * progress,
        )
    }
}

extension Rect {
    func isApproximatelyEqual(to other: Rect) -> Bool {
        abs(topLeftX - other.topLeftX) < 0.5 &&
            abs(topLeftY - other.topLeftY) < 0.5 &&
            abs(width - other.width) < 0.5 &&
            abs(height - other.height) < 0.5
    }
}

enum LayoutReason: Equatable {
    case standard
    /// Reason for the cur temp layout is macOS native fullscreen, minimize, or hide
    case macos(prevParentKind: NonLeafTreeNodeKind)
}

extension Window {
    var isFloating: Bool { // todo drop. It will be a source of bugs when sticky is introduced
        switch windowParentCases {
            case .floatingWindowsContainer: true
            case .macosFullscreenWindowsContainer: false
            case .macosHiddenAppsWindowsContainer: false
            case .macosMinimizedWindowsContainer: false
            case .macosPopupWindowsContainer: false
            case .tilingContainer: false
            case .unbound: false
        }
    }

    @discardableResult
    @MainActor
    func bindAsFloatingWindow(to workspace: Workspace) -> BindingData? {
        bind(to: workspace.floatingWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }

    func asMacWindow() -> MacWindow { self as! MacWindow }
}
