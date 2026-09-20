import CoreGraphics
import Darwin
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 7 else { exit(2) }

let sequenceState = arguments[0]
let sequenceFile = arguments[1]
let expectedFile = arguments[2]
let hudBinary = arguments[3]
let hudPIDFile = arguments[4]
let watcherPIDFile = arguments[5]
let yabaiBinary = arguments[6]
let files = FileManager.default

enum SelectionControl {
    static var stateFile = ""
    static var sequenceFile = ""

    static func move(_ delta: Int) {
        guard let state = try? String(contentsOfFile: stateFile, encoding: .utf8),
              let current = Int(state.trimmingCharacters(in: .whitespacesAndNewlines)),
              let sequence = try? String(contentsOfFile: sequenceFile, encoding: .utf8) else { return }
        let count = sequence.split(separator: "\n").count
        guard count > 0 else { return }

        var next = current + delta
        if next < 1 { next = count }
        if next > count { next = 1 }
        try? String(next).write(toFile: stateFile, atomically: true, encoding: .utf8)
    }
}

func arrowEventTap(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard type == .keyDown, event.flags.contains(.maskAlternate) else {
        return Unmanaged.passUnretained(event)
    }

    switch event.getIntegerValueField(.keyboardEventKeycode) {
    case 123: // Left Arrow
        SelectionControl.move(-1)
        return nil
    case 124: // Right Arrow
        SelectionControl.move(1)
        return nil
    default:
        return Unmanaged.passUnretained(event)
    }
}

func readTrimmed(_ path: String) -> String? {
    try? String(contentsOfFile: path, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func stopHUD() {
    if let value = readTrimmed(hudPIDFile), let pid = Int32(value) {
        kill(pid, SIGTERM)
    }
    try? files.removeItem(atPath: hudPIDFile)
}

func showHUD() {
    guard files.isExecutableFile(atPath: hudBinary) else { return }

    stopHUD()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: hudBinary)
    process.arguments = [sequenceFile, sequenceState]
    try? process.run()
    try? String(process.processIdentifier).write(toFile: hudPIDFile, atomically: true, encoding: .utf8)
}

SelectionControl.stateFile = sequenceState
SelectionControl.sequenceFile = sequenceFile

let keyDownMask = CGEventMask(1) << CGEventType.keyDown.rawValue
let eventTap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: keyDownMask,
    callback: arrowEventTap,
    userInfo: nil
)
var runLoopSource: CFRunLoopSource?
if let eventTap {
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
}

showHUD()
while CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate) {
    CFRunLoopRunInMode(.defaultMode, 0.02, false)
}

if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes) }

stopHUD()

if let value = readTrimmed(sequenceState), let selected = Int(value),
   let contents = readTrimmed(sequenceFile) {
    let entries = contents.split(separator: "\n").map { line in
        String(line).split(separator: "\t", maxSplits: 1).first.map(String.init) ?? ""
    }
    if selected > 0 && selected <= entries.count {
        let target = entries[selected - 1]
        try? target.write(toFile: expectedFile, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: yabaiBinary)
        process.arguments = ["-m", "space", "--focus", target]
        try? process.run()
        process.waitUntilExit()
    }
}

for path in [sequenceState, sequenceFile, hudPIDFile, watcherPIDFile] {
    try? files.removeItem(atPath: path)
}
