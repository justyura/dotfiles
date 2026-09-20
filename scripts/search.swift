import Cocoa
import Carbon
import Darwin

// One keyboard owner even when Option+O repeats while held.
try? FileManager.default.createDirectory(atPath: NSHomeDirectory() + "/.cache/sketchybar",
                                         withIntermediateDirectories: true)
let searchLock = open(NSHomeDirectory() + "/.cache/sketchybar/search.lock", O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
guard searchLock >= 0, flock(searchLock, LOCK_EX | LOCK_NB) == 0 else { exit(1) }

func selectRime() {
    let filter = [kTISPropertyInputSourceID: "im.rime.inputmethod.Squirrel.Hans"] as CFDictionary
    guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
          let source = sources.first else { return }
    TISSelectInputSource(source)
}

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
            styleMask: [.borderless],
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
        // Return used to commit Chinese composition must not launch a search.
        if let editor = searchField.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { (NSApp.delegate as? AppDelegate)?.cancel(); return }

        let url: URL?
        if query.contains(".") && !query.contains(" ") {
            let withScheme = query.hasPrefix("http") ? query : "https://\(query)"
            url = URL(string: withScheme)
        } else {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            url = URL(string: "https://www.kagi.com/search?q=\(encoded)")
        }

        if let url = url {
            NSWorkspace.shared.open(url)
        }
        (NSApp.delegate as? AppDelegate)?.finish(code: 0)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: SearchWindow!
    var ready = false
    var finishing = false
    let previousApp = NSWorkspace.shared.frontmostApplication

    func finish(code: Int32) {
        guard !finishing else { return }
        finishing = true
        (window?.searchField.currentEditor() as? NSTextView)?.unmarkText()
        window?.orderOut(nil)
        exit(code)
    }

    func cancel() {
        previousApp?.activate(options: [])
        finish(code: 1)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = SearchWindow()
        // 让标准编辑快捷键（Cmd+V/C/X/A）能工作
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Copy",  action: #selector(NSText.copy(_:)),  keyEquivalent: "c")
    editMenu.addItem(withTitle: "Cut",   action: #selector(NSText.cut(_:)),   keyEquivalent: "x")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    let editMenuItem = NSMenuItem()
    editMenuItem.submenu = editMenu

    let mainMenu = NSMenu()
    mainMenu.addItem(editMenuItem)
    NSApp.mainMenu = mainMenu
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.searchField)
        window.searchField.currentEditor()?.inputContext?.activate()
        selectRime()
        ready = true

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                // Let Rime cancel its preedit before closing the search panel.
                if (self.window.searchField.currentEditor() as? NSTextView)?.hasMarkedText() == true { return event }
                self.cancel()
                return nil
            }
            return event
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        if ready { finish(code: 1) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
