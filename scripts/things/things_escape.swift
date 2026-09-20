import AppKit
import ApplicationServices

func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}
func elementAttribute(_ element: AXUIElement, _ key: String) -> AXUIElement? {
    guard let value = attribute(element, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

func escapeAction() -> String {
    guard let app = NSWorkspace.shared.frontmostApplication,
          app.bundleIdentifier == "com.culturedcode.ThingsMac" else { return "ignore" }
    // Never prompt for permissions or hide on incomplete accessibility information.
    guard AXIsProcessTrusted() else { return "native" }
    let source = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(source, 0.02)
    guard let window = elementAttribute(source, "AXFocusedWindow"),
          attribute(window, "AXSubrole") as? String == "AXStandardWindow",
          attribute(window, "AXModal") as? Bool != true,
          let focused = elementAttribute(source, "AXFocusedUIElement"),
          let role = attribute(focused, "AXRole") as? String else { return "native" }
    let listRoles: Set<String> = ["AXTable", "AXOutline", "AXList", "AXRow", "AXCell", "AXScrollArea"]
    guard listRoles.contains(role) else { return "native" }
    let nativeRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXSheet", "AXPopover", "AXMenu"]
    var ancestor = focused
    for _ in 0..<20 {
        guard let role = attribute(ancestor, "AXRole") as? String else { return "native" }
        if nativeRoles.contains(role) { return "native" }
        if role == "AXWindow" { return CFEqual(ancestor, window) ? "hide" : "native" }
        guard let parent = elementAttribute(ancestor, "AXParent") else { return "native" }
        ancestor = parent
    }
    return "native"
}
struct NavigationTarget: Equatable {
    let key: Int64
    let flags: CGEventFlags
    var opensEditor: Bool { key == 3 || key == 49 || key == 46 }
    var repeats: Bool { [123, 124, 125, 126].contains(key) }
    var yank: Bool { key == -1 || key == -2 }
    var insertAbove: Bool = false
}

func navigationTarget(key: Int64, flags: CGEventFlags) -> NavigationTarget? {
    guard flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else { return nil }
    if flags.contains(.maskShift) {
        switch key {
        case 38: return NavigationTarget(key: 125, flags: .maskCommand) // J -> Cmd+Down
        case 40: return NavigationTarget(key: 126, flags: .maskCommand) // K -> Cmd+Up
        case 31: return NavigationTarget(key: 49, flags: [], insertAbove: true) // O
        case 16: return NavigationTarget(key: -2, flags: []) // Y -> entire project
        case 5: return NavigationTarget(key: 125, flags: .maskAlternate) // G -> last
        case 45: return NavigationTarget(key: -8, flags: []) // N -> show Now
        case 8: return NavigationTarget(key: -9, flags: []) // C -> merge selection
        default: return nil
        }
    }
    switch key {
    case 4: return NavigationTarget(key: 123, flags: [])   // h -> Left
    case 38: return NavigationTarget(key: 125, flags: [])  // j -> Down
    case 40: return NavigationTarget(key: 126, flags: [])  // k -> Up
    case 37: return NavigationTarget(key: 124, flags: [])  // l -> Right
    case 44: return NavigationTarget(key: 3, flags: .maskCommand) // / -> Cmd+F
    case 31: return NavigationTarget(key: 49, flags: []) // o -> Space (new below)
    case 16: return NavigationTarget(key: -1, flags: []) // y -> selection with notes
    case 5, 1: return NavigationTarget(key: -3, flags: []) // g/s prefix
    case 9: return NavigationTarget(key: -5, flags: []) // v -> visual selection
    case 45: return NavigationTarget(key: -7, flags: []) // n -> arrange selected tasks in Now
    case 35: return NavigationTarget(key: -6, flags: []) // p -> play/pause timer
    case 2: return NavigationTarget(key: 51, flags: []) // d -> native Delete
    case 46: return NavigationTarget(key: 46, flags: [.maskCommand, .maskShift]) // m -> Move
    default: return nil
    }
}

struct SelectionMode {
    var active = false
    mutating func leave() -> Bool {
        let wasActive = active
        active = false
        return wasActive
    }
    func target(_ target: NavigationTarget, sourceKey: Int64, flags: CGEventFlags) -> NavigationTarget {
        guard active, flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
              sourceKey == 38 || sourceKey == 40 else { return target }
        return NavigationTarget(key: target.key, flags: .maskShift)
    }
}

// Select the preceding populated row, including a heading at a group boundary.
// Things' native Space then inserts below it, immediately above the original task.
// Do not queue keys or guess an insertion position if AX cannot confirm selection.
func prepareInsertionAbove() -> Bool {
    guard let app = NSWorkspace.shared.frontmostApplication,
          app.bundleIdentifier == "com.culturedcode.ThingsMac" else { return false }
    let source = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(source, 0.02)
    guard var table = elementAttribute(source, "AXFocusedUIElement") else { return false }
    for _ in 0..<20 {
        if attribute(table, "AXRole") as? String == "AXTable" { break }
        guard let parent = elementAttribute(table, "AXParent") else { return false }
        table = parent
    }
    guard let rows = attribute(table, "AXRows") as? [AXUIElement],
          let selected = attribute(table, "AXSelectedRows") as? [AXUIElement],
          selected.count == 1,
          let index = rows.firstIndex(where: { CFEqual($0, selected[0]) }), index > 0 else { return false }
    let started = ProcessInfo.processInfo.systemUptime
    for previous in rows[..<index].reversed() {
        guard ProcessInfo.processInfo.systemUptime - started < 0.04 else { return false }
        guard let children = attribute(previous, "AXChildren") as? [AXUIElement],
              !children.isEmpty else { continue }
        guard AXUIElementSetAttributeValue(table, "AXSelectedRows" as CFString, [previous] as CFArray) == .success else { return false }
        if let now = attribute(table, "AXSelectedRows") as? [AXUIElement],
           now.count == 1, CFEqual(now[0], previous) { return true }
        _ = AXUIElementSetAttributeValue(table, "AXSelectedRows" as CFString, selected as CFArray)
        return false
    }
    return false
}

// Copy is asynchronous so Apple Events never block the keyboard event tap.
// One read at a time, no backlog; discard results if focus/selection or clipboard changes.
var yankProcess: Process?
var mergeProcess: Process?
enum SelectionAction { case copy, search, timer, now, merge }
func readSelectedItems(all: Bool = false, action: SelectionAction = .copy) {
    let search = action == .search
    let timer = action == .timer
    let merge = action == .merge
    let now = action == .now || merge
    if merge && mergeProcess != nil { return }
    guard yankProcess == nil, let app = NSWorkspace.shared.frontmostApplication else { return }
    let source = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(source, 0.02)
    guard let window = elementAttribute(source, "AXFocusedWindow"),
          let title = attribute(window, "AXTitle") as? String,
          let focused = elementAttribute(source, "AXFocusedUIElement") else { return }
    let selection = attribute(focused, "AXSelectedRows") as? [AXUIElement] ?? []
    let clipboardVersion = NSPasteboard.general.changeCount
    let script = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent(now ? "things_now_selection.js" : timer ? "things_timer_selection.js" : "things_yank.js")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-l", "JavaScript", script.path] + ((timer || now) ? [title] : [all ? "project" : "selection", title])
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.standardError
    do { try process.run() } catch { fputs("Could not start Things copy reader\n", stderr); return }
    yankProcess = process
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
        if yankProcess === process, process.isRunning { process.terminate() }
    }
    DispatchQueue.global(qos: .userInitiated).async {
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        DispatchQueue.main.async {
            defer { if yankProcess === process { yankProcess = nil } }
            guard process.terminationStatus == 0,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                  let currentWindow = elementAttribute(source, "AXFocusedWindow"), CFEqual(window, currentWindow),
                  attribute(currentWindow, "AXTitle") as? String == title,
                  let currentFocus = elementAttribute(source, "AXFocusedUIElement"), CFEqual(focused, currentFocus),
                  escapeAction() == "hide", (search || timer || now || NSPasteboard.general.changeCount == clipboardVersion) else { return }
            if !all {
                let current = attribute(currentFocus, "AXSelectedRows") as? [AXUIElement] ?? []
                guard current.count == selection.count,
                      zip(current, selection).allSatisfy({ CFEqual($0.0, $0.1) }) else { return }
            }
            guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if now {
                guard let tasks = payload["tasks"] as? [[String: Any]], !tasks.isEmpty,
                      let data = try? JSONSerialization.data(withJSONObject: tasks),
                      let json = String(data: data, encoding: .utf8) else { return }
                if merge {
                    let worker = Process()
                    worker.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                    let script = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("things_merge.py")
                    worker.arguments = [script.path, "--tasks", json, "--window", title]
                    worker.standardOutput = FileHandle.nullDevice
                    worker.standardError = FileHandle.standardError
                    worker.terminationHandler = { _ in DispatchQueue.main.async { mergeProcess = nil } }
                    do { try worker.run(); mergeProcess = worker } catch { fputs("Could not start merge worker\n", stderr) }
                } else { runNow(action: "enqueue", tasks: json) }
                return
            }
            if timer {
                guard let json = String(data: data, encoding: .utf8) else { return }
                let worker = Process()
                worker.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                let timerScript = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("things_timer.py")
                worker.arguments = [timerScript.path, "toggle", "--task", json]
                worker.standardOutput = FileHandle.nullDevice
                worker.standardError = FileHandle.standardError
                try? worker.run()
                return
            }
            guard let text = payload["text"] as? String, !text.isEmpty else { return }
            if search {
                if let titles = payload["titles"] as? [String] { searchTasks(titles) }
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

func runNow(action: String, tasks: String = "[]") {
    let script = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("things_now.py")
    let worker = Process()
    worker.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    worker.arguments = [script.path, action, "--tasks", tasks]
    worker.standardOutput = FileHandle.nullDevice
    worker.standardError = FileHandle.standardError
    try? worker.run()
}

func searchTasks(_ titles: [String]) {
    guard !titles.isEmpty, let data = try? JSONSerialization.data(withJSONObject: titles),
          let argument = String(data: data, encoding: .utf8) else { return }
    let script = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("things_search.js")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-l", "JavaScript", script.path, argument]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.standardError
    process.terminationHandler = { child in
        guard child.terminationStatus == 0, titles.count == 1 else { return }
        let focus = Process()
        focus.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yabai")
        focus.arguments = ["-m", "space", "--focus", "3"]
        try? focus.run()
    }
    do { try process.run() } catch { fputs("Could not open Safari search\n", stderr) }
}

struct KeySequence {
    var pending: (key: Int64, time: Double, pid: pid_t)?
    mutating func resolve(key: Int64, flags: CGEventFlags, now: Double, pid: pid_t) -> NavigationTarget? {
        let previous = pending
        pending = nil
        guard flags.intersection([.maskShift, .maskCommand, .maskControl, .maskAlternate]).isEmpty else {
            return navigationTarget(key: key, flags: flags)
        }
        if key == 5, let previous, previous.pid == pid, now - previous.time < 0.8 {
            if previous.key == 5 { return NavigationTarget(key: 126, flags: .maskAlternate) }
            if previous.key == 1 { return NavigationTarget(key: -4, flags: []) } // sg
        }
        if key == 5 || key == 1 {
            pending = (key, now, pid)
            return nil
        }
        return navigationTarget(key: key, flags: flags)
    }
}

func remap(_ event: CGEvent, to target: NavigationTarget) -> Unmanaged<CGEvent> {
    // Rewrite the original event, including its key-up; no queued/synthetic shortcuts.
    event.keyboardSetUnicodeString(stringLength: 0, unicodeString: nil)
    event.setIntegerValueField(.keyboardEventKeycode, value: target.key)
    event.flags = target.flags
    return Unmanaged.passUnretained(event)
}

enum NavigationPress {
    case consumed
    case native
    case mapped(NavigationTarget, pid_t)
}

// Each physical press owns one decision until key-up. In particular, a repeat after
// Things closes an editor cannot turn that same editing Escape into a hide action.
struct EscapePress {
    var held = false
    var consumed = false
    mutating func down(isRepeat: Bool, decide: () -> Bool) -> (consume: Bool, hide: Bool) {
        if held { return (consumed, false) }
        held = true
        // A repeat arriving after tap recovery has no trustworthy initial key-down.
        consumed = !isRepeat && decide()
        return (consumed, consumed)
    }
    mutating func up() -> Bool {
        let result = consumed
        held = false
        consumed = false
        return result
    }
}

let stateDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("things_escape_\(getuid())")
try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
let lockPath = stateDirectory.appendingPathComponent("watcher.lock").path
let lockFD = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
let command = CommandLine.arguments.dropFirst().first ?? "--inspect"
if command == "--request-permission" {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    let trusted = AXIsProcessTrustedWithOptions(options)
    print(trusted ? "Accessibility authorized" : "Accessibility permission requested; enable things_escape in System Settings")
    exit(trusted ? 0 : 1)
}
if command == "--running" {
    guard lockFD >= 0 else { exit(1) }
    exit(flock(lockFD, LOCK_EX | LOCK_NB) == 0 ? 1 : 0)
}
if command == "--self-test" {
    var press = EscapePress()
    var decisions = 0
    let editing = press.down(isRepeat: false) { decisions += 1; return false }
    assert(!editing.consume && !editing.hide)
    let afterEditorClosed = press.down(isRepeat: true) { decisions += 1; return true }
    assert(!afterEditorClosed.consume && !afterEditorClosed.hide && decisions == 1)
    assert(!press.up())
    let list = press.down(isRepeat: false) { decisions += 1; return true }
    assert(list.consume && list.hide && decisions == 2)
    assert(!press.down(isRepeat: true) { fatalError("Must not recheck repeats") }.hide)
    assert(press.up())
    assert(!press.down(isRepeat: true) { fatalError("Orphan repeats must pass") }.hide)
    let expected: [(Int64, Int64)] = [(4,123),(38,125),(40,126),(37,124),(44,3),(31,49),(16,-1),(2,51),(46,46)]
    for (key, output) in expected {
        assert(navigationTarget(key: key, flags: [])?.key == output)
        assert(navigationTarget(key: key, flags: .maskCommand) == nil)
        assert(navigationTarget(key: key, flags: .maskControl) == nil)
        assert(navigationTarget(key: key, flags: .maskAlternate) == nil)
    }
    assert(navigationTarget(key: 38, flags: .maskShift) == NavigationTarget(key: 125, flags: .maskCommand))
    assert(navigationTarget(key: 40, flags: .maskShift) == NavigationTarget(key: 126, flags: .maskCommand))
    assert(navigationTarget(key: 31, flags: .maskShift) == NavigationTarget(key: 49, flags: [], insertAbove: true))
    assert(navigationTarget(key: 31, flags: [])!.opensEditor)
    assert(navigationTarget(key: 31, flags: .maskShift)!.opensEditor)
    assert(!navigationTarget(key: 38, flags: [])!.opensEditor)
    assert(navigationTarget(key: 16, flags: .maskShift)?.key == -2)
    assert(navigationTarget(key: 46, flags: [])?.flags == [.maskCommand, .maskShift])
    for key: Int64 in [2, 16, 31, 44, 46] { assert(!navigationTarget(key: key, flags: [])!.repeats) }
    assert(navigationTarget(key: 46, flags: [])!.opensEditor)
    assert(navigationTarget(key: 2, flags: .maskShift) == nil)
    assert(navigationTarget(key: 44, flags: .maskShift) == nil) // ? remains ?
    assert(navigationTarget(key: 4, flags: .maskShift) == nil)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 38, keyDown: down)!
        let target = NavigationTarget(key: 125, flags: .maskCommand)
        _ = remap(event, to: target)
        assert(event.getIntegerValueField(.keyboardEventKeycode) == 125)
        assert(event.flags == .maskCommand)
    }
    assert(navigationTarget(key: 45, flags: [])?.key == -7)
    assert(navigationTarget(key: 35, flags: [])?.key == -6)
    assert(navigationTarget(key: 45, flags: .maskCommand) == nil)
    assert(navigationTarget(key: 45, flags: .maskShift)?.key == -8)
    assert(navigationTarget(key: 8, flags: .maskShift)?.key == -9)
    assert(navigationTarget(key: 8, flags: []) == nil)
    assert(navigationTarget(key: 8, flags: [.maskCommand, .maskShift]) == nil)
    assert(!navigationTarget(key: 45, flags: [])!.repeats)
    var visual = SelectionMode(active: true)
    let down = NavigationTarget(key: 125, flags: [])
    assert(visual.target(down, sourceKey: 38, flags: []) == NavigationTarget(key: 125, flags: .maskShift))
    assert(visual.target(NavigationTarget(key: 126, flags: []), sourceKey: 40, flags: []) == NavigationTarget(key: 126, flags: .maskShift))
    assert(visual.target(down, sourceKey: 38, flags: .maskCommand) == down)
    var visualEscape = EscapePress()
    assert(visualEscape.down(isRepeat: false) { visual.leave() }.consume)
    assert(!visual.active)
    assert(visualEscape.down(isRepeat: true) { fatalError("Visual Esc repeat must not hide") }.consume)
    assert(visualEscape.up())
    assert(visual.target(down, sourceKey: 38, flags: []) == down)
    assert(!visual.leave())
    assert(navigationTarget(key: 9, flags: [])?.key == -5)
    assert(navigationTarget(key: 9, flags: .maskCommand) == nil)
    var seq = KeySequence()
    assert(seq.resolve(key: 5, flags: [], now: 1, pid: 1) == nil)
    assert(seq.resolve(key: 5, flags: [], now: 1.2, pid: 1) == NavigationTarget(key: 126, flags: .maskAlternate))
    assert(seq.resolve(key: 1, flags: [], now: 2, pid: 1) == nil)
    assert(seq.resolve(key: 5, flags: [], now: 2.3, pid: 1)?.key == -4)
    assert(seq.resolve(key: 5, flags: [], now: 3, pid: 1) == nil)
    assert(seq.resolve(key: 5, flags: [], now: 4, pid: 1) == nil) // expired
    assert(seq.resolve(key: 5, flags: [], now: 4.2, pid: 2) == nil) // switched app
    assert(seq.resolve(key: 5, flags: .maskShift, now: 4.3, pid: 2) == NavigationTarget(key: 125, flags: .maskAlternate))
    print("Escape and Things navigation regression checks passed")
    exit(0)
}
if command != "--watch" {
    print(escapeAction())
    exit(0)
}
guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
guard AXIsProcessTrusted() else {
    fputs("Escape watcher cannot access accessibility; original Escape remains untouched.\n", stderr)
    exit(1)
}

var press = EscapePress()
var navigationPresses: [Int64: NavigationPress] = [:]
// Suppress navigation after / or o/O until Things exposes the editor.
var editorPending = false
var sequence = KeySequence()
var selectionMode = SelectionMode()
var selectionWindow: AXUIElement?
var selectionTitle: String?
var eventTap: CFMachPort?
let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue) | (CGEventMask(1) << CGEventType.leftMouseDown.rawValue) | (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                            options: .defaultTap, eventsOfInterest: mask,
                            callback: { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Never reinterpret a still-held editing Escape after a timeout/re-enable.
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if type == .leftMouseDown || type == .rightMouseDown {
        sequence.pending = nil
        _ = selectionMode.leave()
        editorPending = false // A click can select a search result without another key.
        return Unmanaged.passUnretained(event)
    }
    let key = event.getIntegerValueField(.keyboardEventKeycode)
    let app = NSWorkspace.shared.frontmostApplication
    let inThings = app?.bundleIdentifier == "com.culturedcode.ThingsMac"
    if !inThings { editorPending = false; sequence.pending = nil; _ = selectionMode.leave() }
    if type == .keyDown, selectionMode.active, let app {
        let source = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(source, 0.02)
        if let window = elementAttribute(source, "AXFocusedWindow"), let original = selectionWindow,
           CFEqual(window, original), attribute(window, "AXTitle") as? String == selectionTitle,
           escapeAction() == "hide" {
            // Remain in visual mode only in the same non-editing list.
        } else { _ = selectionMode.leave() }
    }
    if key == 53 { sequence.pending = nil }
    if key != 53 {
        if type == .keyUp, let route = navigationPresses.removeValue(forKey: key) {
            if case .consumed = route { return nil }
            if case let .mapped(target, pid) = route {
                return inThings && app?.processIdentifier == pid ? remap(event, to: target) : nil
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        // Observe the editor for ALL keys, including letters outside hjkl
        // and Return; otherwise the first navigation key after searching stays blocked.
        if editorPending, inThings, escapeAction() != "hide" { editorPending = false }
        if let route = navigationPresses[key] {
            switch route {
            case .consumed: return nil
            case .native: return Unmanaged.passUnretained(event)
            case let .mapped(target, pid):
                // Never type a held navigation letter into a newly opened editor/app.
                guard inThings, app?.processIdentifier == pid, target.repeats,
                      !editorPending, (target.flags != .maskShift || selectionMode.active),
                      escapeAction() == "hide" else { return nil }
                return remap(event, to: target)
            }
        }
        guard navigationTarget(key: key, flags: event.flags) != nil else {
            sequence.pending = nil
            return Unmanaged.passUnretained(event)
        }
        navigationPresses[key] = .native
        let started = ProcessInfo.processInfo.systemUptime
        let age = started - Double(event.timestamp) / 1_000_000_000
        guard inThings, age >= -0.01, age < 0.1,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
            return Unmanaged.passUnretained(event)
        }
        let isList = escapeAction() == "hide"
        if editorPending {
            sequence.pending = nil
            if !isList { editorPending = false }
            return Unmanaged.passUnretained(event)
        }
        guard isList, ProcessInfo.processInfo.systemUptime - started < 0.075,
              let app, app.isActive else {
            sequence.pending = nil
            return Unmanaged.passUnretained(event)
        }
        guard let resolved = sequence.resolve(key: key, flags: event.flags, now: started, pid: app.processIdentifier) else {
            navigationPresses[key] = .consumed
            return nil
        }
        if resolved.key == -5 {
            navigationPresses[key] = .consumed
            if !selectionMode.leave() {
                let source = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(source, 0.02)
                selectionWindow = elementAttribute(source, "AXFocusedWindow")
                selectionTitle = selectionWindow.flatMap { attribute($0, "AXTitle") as? String }
                selectionMode.active = selectionWindow != nil && selectionTitle != nil
            }
            return nil
        }
        let target = selectionMode.target(resolved, sourceKey: key, flags: event.flags)
        if target.key == -9 {
            navigationPresses[key] = .consumed
            readSelectedItems(action: .merge)
            return nil
        }
        if target.key == -7 {
            navigationPresses[key] = .consumed
            readSelectedItems(action: .now)
            return nil
        }
        if target.key == -8 {
            navigationPresses[key] = .consumed
            _ = selectionMode.leave()
            runNow(action: "show")
            return nil
        }
        if target.key == -6 {
            navigationPresses[key] = .consumed
            readSelectedItems(action: .timer)
            return nil
        }
        if target.key == -4 {
            navigationPresses[key] = .consumed
            readSelectedItems(action: .search)
            return nil
        }
        if target.yank {
            navigationPresses[key] = .consumed
            readSelectedItems(all: target.key == -2)
            return nil
        }
        if target.insertAbove, !prepareInsertionAbove() {
            // Consume an unavailable insertion instead of starting Type Travel with O.
            navigationPresses[key] = .consumed
            return nil
        }
        navigationPresses[key] = .mapped(target, app.processIdentifier)
        if target.opensEditor { editorPending = true; _ = selectionMode.leave() }
        if key == 2 { _ = selectionMode.leave() }
        return remap(event, to: target)
    }
    if type == .keyUp {
        return press.up() ? nil : Unmanaged.passUnretained(event)
    }
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    let decision = press.down(isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0) {
        if editorPending {
            editorPending = false
            return false
        }
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        guard event.flags.intersection(modifiers).isEmpty else { return false }
        let started = ProcessInfo.processInfo.systemUptime
        let eventTime = Double(event.timestamp) / 1_000_000_000
        // Old events are never acted upon later. Slow/failed focus checks also fail open.
        guard started - eventTime < 0.1, started >= eventTime - 0.01,
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.culturedcode.ThingsMac",
              escapeAction() == "hide",
              ProcessInfo.processInfo.systemUptime - started < 0.075,
              app.isActive else { return false }
        // A visual Escape is consumed by this press, including repeats and key-up.
        // A second physical Escape in normal mode may hide Things.
        if selectionMode.leave() { return true }
        // Synchronous native hide: no shell, synthetic Escape, dispatch queue or lock wait.
        return app.hide()
    }
    return decision.consume ? nil : Unmanaged.passUnretained(event)
}, userInfo: nil)
guard let eventTap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
    fputs("Could not install Escape event tap; original Escape remains untouched.\n", stderr)
    exit(1)
}
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)
fputs("Things keyboard watcher ready (Esc, hjkl, /, J/K, o/O, y/Y, d, m, gg/G, sg, v, n/N, p, C)\n", stderr)
CFRunLoopRun()

