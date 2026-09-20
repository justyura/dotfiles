@preconcurrency import AppKit

struct Entry {
    let space: String
    let pids: [pid_t]
}

final class RoundedView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.10, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).fill()
    }
}

final class SpaceCell: NSView {
    private let number = NSTextField(labelWithString: "")

    init(entry: Entry, frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 11

        let icons = entry.pids.prefix(3).compactMap {
            NSRunningApplication(processIdentifier: $0)?.icon
        }
        let iconSize: CGFloat = 38
        let overlap: CGFloat = icons.count > 1 ? 25 : iconSize
        let iconRowWidth = iconSize + CGFloat(max(0, icons.count - 1)) * overlap
        let startX = (frame.width - iconRowWidth) / 2

        for (offset, icon) in icons.enumerated() {
            let imageView = NSImageView(frame: NSRect(
                x: startX + CGFloat(offset) * overlap,
                y: 36,
                width: iconSize,
                height: iconSize
            ))
            imageView.image = icon
            imageView.imageScaling = .scaleProportionallyUpOrDown
            addSubview(imageView)
        }

        if icons.isEmpty, let fallback = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) {
            let imageView = NSImageView(frame: NSRect(x: (frame.width - 38) / 2, y: 36, width: 38, height: 38))
            imageView.image = fallback
            imageView.contentTintColor = .lightGray
            addSubview(imageView)
        }

        if entry.pids.count > 3 {
            let more = NSTextField(labelWithString: "+\(entry.pids.count - 3)")
            more.frame = NSRect(x: frame.width - 28, y: 67, width: 24, height: 15)
            more.alignment = .center
            more.font = NSFont.systemFont(ofSize: 9, weight: .bold)
            more.textColor = .white
            more.wantsLayer = true
            more.layer?.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 0.9).cgColor
            more.layer?.cornerRadius = 5
            addSubview(more)
        }

        number.stringValue = entry.space
        number.frame = NSRect(x: 5, y: 7, width: frame.width - 10, height: 24)
        number.alignment = .center
        number.font = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        addSubview(number)
    }

    required init?(coder: NSCoder) { nil }

    func setSelected(_ selected: Bool, isOrigin: Bool) {
        layer?.backgroundColor = selected
            ? NSColor.systemGreen.cgColor
            : NSColor.clear.cgColor
        layer?.borderWidth = !selected && isOrigin ? 1 : 0
        layer?.borderColor = NSColor(calibratedWhite: 0.45, alpha: 0.7).cgColor
        number.textColor = selected
            ? NSColor(calibratedWhite: 0.08, alpha: 1)
            : (isOrigin ? .white : .lightGray)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else { exit(2) }
let sequenceFile = arguments[0]
let stateFile = arguments[1]

guard let contents = try? String(contentsOfFile: sequenceFile, encoding: .utf8) else { exit(1) }
let entries = contents.split(separator: "\n").compactMap { line -> Entry? in
    let fields = String(line).split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
    guard let space = fields.first, !space.isEmpty else { return nil }
    let pids: [pid_t]
    if fields.count > 1 {
        pids = fields[1].split(separator: ",").compactMap { pid_t($0) }
    } else {
        pids = []
    }
    return Entry(space: String(space), pids: pids)
}
guard !entries.isEmpty else { exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let cellWidth: CGFloat = 96
let cellHeight: CGFloat = 88
let panelWidth = min(max(CGFloat(entries.count) * cellWidth + 32, 260), 1100)
let panelSize = NSSize(width: panelWidth, height: 120)
let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
let origin = NSPoint(x: screen.midX - panelSize.width / 2, y: screen.midY - panelSize.height / 2)

let panel = NSPanel(
    contentRect: NSRect(origin: origin, size: panelSize),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.level = .floating
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.ignoresMouseEvents = true
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

let content = RoundedView(frame: NSRect(origin: .zero, size: panelSize))
let rowWidth = CGFloat(entries.count) * cellWidth
let startX = max(14, (panelWidth - rowWidth) / 2)
var cells: [SpaceCell] = []

for (offset, entry) in entries.enumerated() {
    let cell = SpaceCell(
        entry: entry,
        frame: NSRect(x: startX + CGFloat(offset) * cellWidth + 4, y: 16, width: 88, height: cellHeight)
    )
    content.addSubview(cell)
    cells.append(cell)
}

func selectedIndex() -> Int {
    guard let value = try? String(contentsOfFile: stateFile, encoding: .utf8),
          let index = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
    return index
}

var lastSelection = -1
func refreshSelection() {
    let selection = selectedIndex()
    guard selection != lastSelection else { return }
    lastSelection = selection
    for (offset, cell) in cells.enumerated() {
        cell.setSelected(offset + 1 == selection, isOrigin: offset == 0)
    }
}

panel.contentView = content
refreshSelection()
panel.orderFrontRegardless()

Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { _ in
    refreshSelection()
}
DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
    app.terminate(nil)
}

app.run()
