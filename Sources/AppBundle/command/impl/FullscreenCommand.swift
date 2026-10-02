import AppKit
import Common

struct FullscreenCommand: Command {
    let args: FullscreenCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else {
            return .fail(io.err(noWindowIsFocused))
        }
        let wasCenteredFullscreen = window.isFullscreen && window.isCenteredFullscreen
        let requestedCenteredFullscreen = args.centered
        let requestedWidthPercent = CGFloat(args.effectiveWidthPercent)
        let requestedHeightPercent = CGFloat(args.effectiveHeightPercent)
        let requestedGeometryMatchesCurrent = window.isFullscreen &&
            (
                requestedCenteredFullscreen
                    ? window.isCenteredFullscreen &&
                    window.noOuterGapsInFullscreen == args.noOuterGaps &&
                    window.centeredFullscreenWidthPercent == requestedWidthPercent &&
                    window.centeredFullscreenHeightPercent == requestedHeightPercent
                    : !window.isCenteredFullscreen
            )
        let newState: Bool = switch args.toggle {
            case .on: true
            case .off: false
            case .toggle: !requestedGeometryMatchesCurrent
        }
        let newCenteredFullscreen = newState && requestedCenteredFullscreen
        let explicitAnimationPreferenceChanges = requestedGeometryMatchesCurrent &&
            requestedCenteredFullscreen &&
            args.animation.map { $0 != window.centeredFullscreenAnimationEnabled } == true
        let isNoop = newState
            ? requestedGeometryMatchesCurrent && !explicitAnimationPreferenceChanges
            : !window.isFullscreen
        if isNoop {
            switch args.failIfNoop {
                case true: return .fail
                case false:
                    let msg = newState
                        ? "Already fullscreen. Tip: use --fail-if-noop to exit with non-zero code"
                        : "Already not fullscreen. Tip: use --fail-if-noop to exit with non-zero code"
                    return .succ(io.err(msg))
            }
        }

        let transitionAnimationEnabled = if newCenteredFullscreen {
            args.animation ?? (requestedGeometryMatchesCurrent ? window.centeredFullscreenAnimationEnabled : false)
        } else if wasCenteredFullscreen {
            args.animation ?? window.centeredFullscreenAnimationEnabled
        } else {
            false
        }
        let geometryWillChange = newState ? !requestedGeometryMatchesCurrent : window.isFullscreen
        window.shouldAnimateNextLayoutFromCentered =
            geometryWillChange && (wasCenteredFullscreen || newCenteredFullscreen) && transitionAnimationEnabled
        if explicitAnimationPreferenceChanges && !transitionAnimationEnabled {
            window.cancelCenteredFullscreenTransition()
        }
        window.isFullscreen = newState
        window.isCenteredFullscreen = newCenteredFullscreen
        window.noOuterGapsInFullscreen = newState && args.noOuterGaps
        if newCenteredFullscreen {
            window.centeredFullscreenWidthPercent = requestedWidthPercent
            window.centeredFullscreenHeightPercent = requestedHeightPercent
            window.centeredFullscreenAnimationEnabled = transitionAnimationEnabled
        } else {
            window.centeredFullscreenWidthPercent = 50
            window.centeredFullscreenHeightPercent = 50
            window.centeredFullscreenAnimationEnabled = false
        }

        // Focus on its own workspace
        window.markAsMostRecentChild()
        return .succ
    }
}

let noWindowIsFocused = "No window is focused"
