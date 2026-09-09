import AppKit

@MainActor private var focusFollowsMouseMonitor: Any? = nil
@MainActor private var focusFollowsTask: Task<(), any Error>? = nil

@MainActor func syncFocusFollowsMouse(_ config: Config) {
    if config.focusFollowsMouse.enabled == (focusFollowsMouseMonitor != nil) {
        return
    }

    if !config.focusFollowsMouse.enabled {
        NSEvent.removeMonitor(focusFollowsMouseMonitor.orDie())
        focusFollowsMouseMonitor = nil
        focusFollowsTask?.cancel()
        focusFollowsTask = nil
        return
    }

    // Interestingly, this callback seems to not fire when the mouse is down which is good,
    // because this is how I want it to work for windows/tabs/files dragging
    focusFollowsMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { @MainActor event in
        let location = event.locationInWindow.withYAxisFlipped
        focusFollowsTask?.cancel()
        focusFollowsTask = Task.startUnstructured { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try checkCancellation()
            // Ignores macOS menubar dropdown, but, unfortunately, it doesn't ignore non-native menu-like fake windows.
            // todo: It would be cool to somehow reuse isWindowHeuristic logic here
            let axWindowUnderMouse = await getAxWindowUnderMouse(location)
            if axWindowUnderMouse.isWindow == false { return }
            try checkCancellation()
            let workspace = location.monitorApproximation.activeWorkspace
            var window: Window? = nil
            for child in workspace.floatingWindowsContainer.mruChildren {
                try checkCancellation()
                guard let child = child as? Window else { continue }
                guard let rect = try await child.getAxRect(.cancellable) else { continue }
                if rect.contains(location) {
                    window = child
                    break
                }
            }
            if window == nil,
               let windowId = axWindowUnderMouse.windowId,
               let hitWindow = Window.get(byId: windowId),
               hitWindow.nodeWorkspace == workspace,
               hitWindow.isFullscreen,
               hitWindow.isCenteredFullscreen
            {
                switch hitWindow.windowParentCases {
                    case .tilingContainer:
                        window = hitWindow
                    default:
                        break
                }
            }
            if window == nil {
                let fullscreenWindow = workspace.rootTilingContainer.mostRecentWindowRecursive
                let centeredFullscreenRect: Rect? = if let fullscreenWindow,
                                                       fullscreenWindow.isFullscreen,
                                                       fullscreenWindow.isCenteredFullscreen
                {
                    try? await fullscreenWindow.getAxRect(.cancellable)
                } else {
                    nil
                }
                try checkCancellation()
                window = location.findWindowRecursively(
                    in: workspace.rootTilingContainer,
                    virtual: false,
                    fullscreenCoversAll: true,
                    centeredFullscreenRect: centeredFullscreenRect,
                )
            }
            if let window {
                try await runLightSession(.focusFollowsMouse, token) {
                    _ = window.focusWindow()
                    window.nativeFocus()
                }
            }
        }
    }
}

@concurrent
private nonisolated func getAxWindowUnderMouse(_ location: CGPoint) async -> (isWindow: Bool?, windowId: UInt32?) {
    let systemwide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    if unsafe AXUIElementCopyElementAtPosition(systemwide, Float(location.x), Float(location.y), &element) != .success {
        return (nil, nil)
    }
    guard let element else { return (nil, nil) }
    let windowElement: AXUIElement
    if let parentWindow = element.get(Ax.parentWindowRecursive) {
        windowElement = parentWindow
    } else if element.get(Ax.roleAttr) == kAXWindowRole {
        windowElement = element
    } else {
        return (false, nil)
    }
    return (true, windowElement.containingWindowId())
}
