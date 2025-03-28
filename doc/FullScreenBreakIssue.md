Understood. This document explains how to ensure the Pomodoro break window appears reliably on macOS, even over fullscreen apps and when using Spaces or Mission Control.

# Ensuring the Break Window Always Appears

## Key Techniques

To make the break window reliably appear, we use the following techniques:

- **NSPanel:** Instead of `NSWindow`, we use `NSPanel` with the `.nonactivatingPanel` style. This allows the window to appear without stealing focus from other apps.
- **Collection Behavior:** The window's `collectionBehavior` is set to `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`. This ensures the window appears in all Spaces, over fullscreen apps, and isn't hidden by Mission Control or app switching.
- **Window Level:** The window's `level` is set to `.screenSaver` to ensure it appears above most other windows.
- **Space Change Monitoring:** We listen for `NSWorkspace.activeSpaceDidChangeNotification` to re-show the break window when the user switches Spaces.
- **Mission Control Handling:** We monitor for screen parameter changes (`NSApplication.didChangeScreenParametersNotification`) and mouse movements to detect when Mission Control is likely active, and then re-show the break window.

## Code Highlights

Here's the key code for setting up the break window:

```swift
import AppKit

func setupBreakWindow() {
    let panel = NSPanel(
        contentRect: screenFrame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false,
        screen: screen
    )
    panel.collectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary,
        .ignoresCycle
    ]
    panel.level = .screenSaver
    panel.hidesOnDeactivate = false
    panel.orderFrontRegardless()
}
```

And here's the code for monitoring Space changes:

```swift
spaceChangeObserver = NotificationCenter.default.addObserver(
    forName: NSWorkspace.activeSpaceDidChangeNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.showBreakWindow()
}
```

## Mission Control Workaround

Since there's no direct notification for Mission Control, we use a workaround:

```swift
missionControlObserver = NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil, 
    queue: .main
) { [weak self] _ in
    self?.isInMissionControl = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        self?.showBreakWindow()
    }
}

NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
    guard let self = self, self.isInMissionControl else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        self.showBreakWindow()
    }
}
```

This approach ensures the break window reappears when the user exits Mission Control.

## Important Notes

- The `ignoresMouseEvents = false` setting on the `NSPanel` ensures that the break window intercepts mouse clicks, preventing interaction with underlying apps.
- The `orderFrontRegardless()` method is used to reliably show the window, even when the app isn't active.

By using these techniques, the PomodoroLock app can enforce breaks effectively, regardless of the user's desktop configuration.