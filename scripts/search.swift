import Cocoa

class SearchField: NSTextField {
    override var acceptsFirstResponder: Bool { true }
}

class RoundedView: NSView {
    var bgColor: NSColor = .black
    var borderColor: NSColor = .gray
    var cornerRadius: CGFloat = 16
    var borderWidth: CGFloat = 1.5

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                xRadius: cornerRadius, yRadius: cornerRadius)
        bgColor.setFill()
        path.fill()
        borderColor.setStroke()
        path.lineWidth = borderWidth
        path.stroke()
    }
}

class SearchWindow: NSPanel {
    let searchField = SearchField()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 64),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .mainMenu + 1
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false

        // Center on screen, slightly above middle
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let x = screenFrame.origin.x + (screenFrame.width - 620) / 2
        let y = screenFrame.origin.y + (screenFrame.height - 64) / 2 + screenFrame.height * 0.15
        setFrameOrigin(NSPoint(x: x, y: y))

        // Tokyo Night colors
        let bg = NSColor(red: 0x1a/255.0, green: 0x1b/255.0, blue: 0x26/255.0, alpha: 0.97)
        let border = NSColor(red: 0x41/255.0, green: 0x48/255.0, blue: 0x68/255.0, alpha: 1.0)
        let fg = NSColor(red: 0xc0/255.0, green: 0xca/255.0, blue: 0xf5/255.0, alpha: 1.0)
        let blue = NSColor(red: 0x7a/255.0, green: 0xa2/255.0, blue: 0xf7/255.0, alpha: 1.0)
        let placeholderColor = NSColor(red: 0x56/255.0, green: 0x5f/255.0, blue: 0x89/255.0, alpha: 1.0)

        // Rounded container drawn with NSBezierPath (no sharp edges)
        let container = RoundedView(frame: NSRect(x: 0, y: 0, width: 620, height: 64))
        container.bgColor = bg
        container.borderColor = border
        container.cornerRadius = 16
        container.borderWidth = 1.5

        // Prompt icon
        let icon = NSTextField(labelWithString: "❯")
        icon.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .bold)
        icon.frame = NSRect(x: 20, y: 16, width: 30, height: 32)
        icon.isEditable = false
        icon.isBezeled = false
        icon.drawsBackground = false
        icon.textColor = blue

        // Search input
        searchField.frame = NSRect(x: 52, y: 12, width: 548, height: 40)
        searchField.font = NSFont.monospacedSystemFont(ofSize: 26, weight: .regular)
        searchField.isBezeled = false
        searchField.focusRingType = .none
        searchField.drawsBackground = false
        searchField.textColor = fg
        searchField.target = self
        searchField.action = #selector(onSubmit)

        if let cell = searchField.cell as? NSTextFieldCell {
            cell.placeholderAttributedString = NSAttributedString(
                string: "Search...",
                attributes: [
                    .foregroundColor: placeholderColor,
                    .font: NSFont.monospacedSystemFont(ofSize: 26, weight: .regular)
                ]
            )
        }

        container.addSubview(icon)
        container.addSubview(searchField)
        contentView = container
    }

    @objc func onSubmit() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { exit(1) }

        let url: URL?
        if query.contains(".") && !query.contains(" ") {
            let withScheme = query.hasPrefix("http") ? query : "https://\(query)"
            url = URL(string: withScheme)
        } else {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            url = URL(string: "https://www.google.com/search?q=\(encoded)")
        }

        if let url = url {
            NSWorkspace.shared.open(url)
        }
        NSApp.terminate(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: SearchWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = SearchWindow()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.searchField)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                exit(1)
            }
            return event
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.activate(ignoringOtherApps: true)
app.run()
