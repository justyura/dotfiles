import AppKit

// Native app hiding avoids Dock minimize/restore animations.
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.culturedcode.ThingsMac").first else {
    exit(1)
}
switch CommandLine.arguments.dropFirst().first {
case "hide":
    if !app.isHidden { _ = app.hide() }
    for _ in 0..<50 where !app.isHidden {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.002))
    }
    exit(app.isHidden ? 0 : 1)
case "show":
    app.unhide()
    _ = app.activate(options: [.activateAllWindows])
    for _ in 0..<50 where app.isHidden || !app.isActive {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.002))
    }
    exit(app.isHidden ? 1 : 0)
case "unhide":
    app.unhide()
    for _ in 0..<100 where app.isHidden {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.002))
    }
    exit(app.isHidden ? 1 : 0)
case "status":
    print(app.isHidden ? "hidden" : "visible")
default:
    exit(2)
}
