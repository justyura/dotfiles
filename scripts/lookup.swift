import Cocoa
import AVFoundation

// MARK: - Custom Views

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

// MARK: - Tokyo Night Colors

struct Theme {
    static let bg = NSColor(red: 0x1a/255.0, green: 0x1b/255.0, blue: 0x26/255.0, alpha: 0.97)
    static let border = NSColor(red: 0x41/255.0, green: 0x48/255.0, blue: 0x68/255.0, alpha: 1.0)
    static let fg = NSColor(red: 0xc0/255.0, green: 0xca/255.0, blue: 0xf5/255.0, alpha: 1.0)
    static let blue = NSColor(red: 0x7a/255.0, green: 0xa2/255.0, blue: 0xf7/255.0, alpha: 1.0)
    static let placeholder = NSColor(red: 0x56/255.0, green: 0x5f/255.0, blue: 0x89/255.0, alpha: 1.0)
}

// MARK: - OpenAI Client

class OpenAIClient {
    let apiKey: String
    let model: String
    var session: URLSession?
    var streamDelegate: StreamDelegate?

    init(model: String = "gpt-4o-mini") {
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty else {
            fatalError("OPENAI_API_KEY not set")
        }
        self.apiKey = key
        self.model = model
    }

    func define(_ word: String, onToken: @escaping (String) -> Void, onDone: @escaping () -> Void, onError: @escaping (Error) -> Void) {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let systemPrompt = """
        Given a word, reply in exactly this format:
        [phonetic transcription]
        Definition: one sentence max.
        Example: one sentence.
        Nothing else.
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": word]
            ],
            "max_tokens": 100,
            "temperature": 0.2,
            "stream": true
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        streamDelegate = StreamDelegate(onToken: onToken, onDone: onDone, onError: onError)
        session = URLSession(configuration: .default, delegate: streamDelegate, delegateQueue: OperationQueue.main)
        session!.dataTask(with: request).resume()
    }
}

// MARK: - SSE Stream Delegate

class StreamDelegate: NSObject, URLSessionDataDelegate {
    let onToken: (String) -> Void
    let onDone: () -> Void
    let onError: (Error) -> Void
    var buffer = ""

    init(onToken: @escaping (String) -> Void, onDone: @escaping () -> Void, onError: @escaping (Error) -> Void) {
        self.onToken = onToken
        self.onDone = onDone
        self.onError = onError
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text

        while let range = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            buffer = String(buffer[range.upperBound...])

            if line.isEmpty { continue }

            let payload: String
            if line.hasPrefix("data: ") {
                payload = String(line.dropFirst(6))
            } else {
                payload = line
            }

            if payload == "[DONE]" {
                onDone()
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String,
                  !content.isEmpty
            else { continue }

            onToken(content)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onError(error)
        }
    }
}

// MARK: - Search Window

class SearchWindow: NSPanel {
    let searchField = SearchField()
    let resultLabel = NSTextField()
    let container: RoundedView
    let icon = NSTextField(labelWithString: "❯")
    let spinner = NSProgressIndicator()
    let client = OpenAIClient()
    let synth = AVSpeechSynthesizer()

    let panelWidth: CGFloat = 620
    let inputHeight: CGFloat = 64
    let maxResultHeight: CGFloat = 320

    var accumulated = ""

    init() {
        container = RoundedView(frame: NSRect(x: 0, y: 0, width: 620, height: 64))

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

        container.bgColor = Theme.bg
        container.borderColor = Theme.border
        container.cornerRadius = 16
        container.borderWidth = 1.5

        icon.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .bold)
        icon.frame = NSRect(x: 20, y: 16, width: 30, height: 32)
        icon.isEditable = false
        icon.isBezeled = false
        icon.drawsBackground = false
        icon.textColor = Theme.blue

        searchField.frame = NSRect(x: 52, y: 12, width: 548, height: 40)
        searchField.font = NSFont.monospacedSystemFont(ofSize: 26, weight: .regular)
        searchField.isBezeled = false
        searchField.focusRingType = .none
        searchField.drawsBackground = false
        searchField.textColor = Theme.fg
        searchField.target = self
        searchField.action = #selector(onSubmit)

        if let cell = searchField.cell as? NSTextFieldCell {
            cell.placeholderAttributedString = NSAttributedString(
                string: "Look up a word...",
                attributes: [
                    .foregroundColor: Theme.placeholder,
                    .font: NSFont.monospacedSystemFont(ofSize: 26, weight: .regular)
                ]
            )
        }

        spinner.style = .spinning
        spinner.frame = NSRect(x: 580, y: 20, width: 24, height: 24)
        spinner.isHidden = true
        spinner.controlSize = .small

        resultLabel.isEditable = false
        resultLabel.isSelectable = true
        resultLabel.isBezeled = false
        resultLabel.drawsBackground = false
        resultLabel.textColor = Theme.fg
        resultLabel.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .regular)
        resultLabel.lineBreakMode = .byWordWrapping
        resultLabel.maximumNumberOfLines = 0
        resultLabel.preferredMaxLayoutWidth = 580
        resultLabel.frame = NSRect(x: 20, y: 0, width: 580, height: 0)
        resultLabel.isHidden = true

        container.addSubview(icon)
        container.addSubview(searchField)
        container.addSubview(spinner)
        container.addSubview(resultLabel)
        contentView = container

        centerOnScreen()
    }

    func centerOnScreen() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let windowHeight = frame.height
        let x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
        let y = screenFrame.origin.y + (screenFrame.height - windowHeight) / 2 + screenFrame.height * 0.15
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc func onSubmit() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        searchField.isEditable = false
        spinner.isHidden = false
        spinner.startAnimation(nil)
        accumulated = ""
        resultLabel.stringValue = ""
        resultLabel.isHidden = false

        // Speak the word
        let utterance = AVSpeechUtterance(string: query)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)

        client.define(query,
            onToken: { [weak self] token in
                guard let self = self else { return }
                self.accumulated += token
                self.resultLabel.stringValue = self.accumulated
                self.resizeToFit()
            },
            onDone: { [weak self] in
                guard let self = self else { return }
                self.spinner.stopAnimation(nil)
                self.spinner.isHidden = true
                self.searchField.isEditable = true
            },
            onError: { [weak self] error in
                guard let self = self else { return }
                self.spinner.stopAnimation(nil)
                self.spinner.isHidden = true
                self.searchField.isEditable = true
                self.accumulated = "Error: \(error.localizedDescription)"
                self.resultLabel.stringValue = self.accumulated
                self.resizeToFit()
            }
        )
    }

    func resizeToFit() {
        let maxWidth: CGFloat = 580
        let size = resultLabel.attributedStringValue.boundingRect(
            with: NSSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textHeight = min(ceil(size.height) + 10, maxResultHeight)
        let totalHeight = inputHeight + textHeight + 24

        resultLabel.frame = NSRect(x: 20, y: 12, width: 580, height: textHeight)

        let newFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y - (totalHeight - frame.height),
            width: panelWidth,
            height: totalHeight
        )
        setFrame(newFrame, display: true)
        container.frame = NSRect(x: 0, y: 0, width: panelWidth, height: totalHeight)

        let inputY = totalHeight - inputHeight
        icon.frame.origin.y = inputY + 16
        searchField.frame.origin.y = inputY + 12
        spinner.frame.origin.y = inputY + 20

        container.needsDisplay = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: SearchWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = SearchWindow()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.searchField)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                NSApp.terminate(nil)
            }
            return event
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.activate(ignoringOtherApps: true)
app.run()
