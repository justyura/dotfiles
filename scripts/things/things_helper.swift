// things_helper：Things 清单弹窗的辅助程序（sketchybar 本身不能测量文字、也不能接收键盘输入）
//
//   things_helper wrap <最大宽度pt> <字号>
//     stdin 每行一个任务名；stdout 每行输出对应任务名按实际字体宽度折行后的各段，段之间用 \u{1f} 分隔
//     （英文优先在空格处断开，中文可在任意字符间断开）
//
//   things_helper input <x> <y> <宽> <高> <字号> [--multi]
//     --multi：连续录入。回车把当前文本打到 stdout 后清空输入框、继续等下一条（不退出），
//     空回车或 esc 才结束；stdin 收 "rect <x> <y> <宽> <高>" 重新定位（每存一条清单会多一行，框要跟着挪）
//     在屏幕坐标（sketchybar 的左上角原点坐标，单位 pt）处显示一个无边框输入框，支持输入法；
//     回车：stdout 输出输入内容并以 0 退出；esc 或失去焦点：以 1 退出
//
// 编译：swiftc -O things_helper.swift -o things_helper（plugins/things_lib.sh 会在需要时自动编译）

import AppKit

let fontName = "SF Pro"

func font(_ size: CGFloat) -> NSFont {
    NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size)
}

// MARK: - wrap

func wrap(_ text: String, maxWidth: CGFloat, font: NSFont) -> [String] {
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    func width(_ s: Substring) -> CGFloat { (String(s) as NSString).size(withAttributes: attrs).width }

    var lines: [String] = []
    var rest = Substring(text)
    while !rest.isEmpty {
        if width(rest) <= maxWidth {
            lines.append(String(rest))
            break
        }
        // 找到能放下的最长前缀
        var end = rest.startIndex
        var idx = rest.startIndex
        while idx < rest.endIndex {
            let next = rest.index(after: idx)
            if width(rest[rest.startIndex..<next]) > maxWidth { break }
            end = next
            idx = next
        }
        if end == rest.startIndex { end = rest.index(after: rest.startIndex) } // 单个字符都放不下时至少放一个
        // 断点落在英文单词中间时，退回到最近的空格
        var cut = end
        if cut < rest.endIndex, rest[cut] != " ", let space = rest[rest.startIndex..<cut].lastIndex(of: " "),
           rest[rest.index(before: cut)].isASCII {
            cut = rest.index(after: space)
        }
        lines.append(String(rest[rest.startIndex..<cut]).trimmingCharacters(in: .whitespaces))
        rest = rest[cut...].drop(while: { $0 == " " })
    }
    return lines.isEmpty ? [""] : lines
}

// MARK: - input

final class InputPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class InputController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    let panel: InputPanel
    let field: NSTextField
    let multi: Bool

    init(rect: NSRect, fontSize: CGFloat, multi: Bool = false) {
        self.multi = multi
        panel = InputPanel(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = NSColor(srgbRed: 0x3b / 255, green: 0x42 / 255, blue: 0x61 / 255, alpha: 1)
        panel.hasShadow = false

        let f = font(fontSize)
        let lineHeight = ceil(f.ascender - f.descender + f.leading) + 2
        field = NSTextField(frame: NSRect(x: 0, y: (rect.height - lineHeight) / 2, width: rect.width, height: lineHeight))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = f
        field.textColor = NSColor(srgbRed: 0xe4 / 255, green: 0xe8 / 255, blue: 0xf7 / 255, alpha: 1)
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.placeholderAttributedString = NSAttributedString(
            string: "New to-do",
            attributes: [.font: f, .foregroundColor: NSColor(srgbRed: 0x73 / 255, green: 0x7a / 255, blue: 0xa2 / 255, alpha: 1)])
        super.init()
        field.delegate = self
        panel.delegate = self
        panel.contentView?.addSubview(field)
    }

    func run() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    // 清单每多一行，占位行就往下挪一行，调用方把新坐标推过来
    func move(to rect: NSRect) {
        let lineHeight = field.frame.height
        panel.setFrame(rect, display: true)
        field.frame = NSRect(x: 0, y: (rect.height - lineHeight) / 2, width: rect.width, height: lineHeight)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            print(field.stringValue)
            guard multi, !field.stringValue.isEmpty else { exit(0) }   // 单条模式、或空回车：结束
            fflush(stdout)
            field.stringValue = ""                                     // 存完清空，接着录下一条
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            exit(1)
        default:
            return false
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        exit(1)
    }
}

// MARK: - main

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: things_helper wrap <width> <size> | input <x> <y> <w> <h> <size>\n".data(using: .utf8)!)
    exit(2)
}

switch args[1] {
case "wrap" where args.count == 4:
    let maxWidth = CGFloat(Double(args[2]) ?? 400)
    let f = font(CGFloat(Double(args[3]) ?? 15))
    while let line = readLine() {
        print(wrap(line, maxWidth: maxWidth, font: f).joined(separator: "\u{1f}"))
    }

case "input" where args.count == 7 || args.count == 8:
    let v = args[2...6].map { CGFloat(Double($0) ?? 0) }
    let (x, yTop, w, h, size) = (v[0], v[1], v[2], v[3], v[4])
    let multi = args.count == 8 && args[7] == "--multi"
    if multi { setvbuf(stdout, nil, _IOLBF, 0) }   // 不设行缓冲的话，存下的内容会卡在管道缓冲区里
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    // sketchybar 坐标以主屏左上角为原点，AppKit 以左下角为原点
    let screenHeight = NSScreen.screens.first?.frame.height ?? 0
    let controller = InputController(rect: NSRect(x: x, y: screenHeight - yTop - h, width: w, height: h),
                                     fontSize: size, multi: multi)
    if multi {
        FileHandle.standardInput.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: " ")
                guard parts.count == 5, parts[0] == "rect" else { continue }
                let r = parts[1...4].map { CGFloat(Double($0) ?? 0) }
                DispatchQueue.main.async {
                    controller.move(to: NSRect(x: r[0], y: screenHeight - r[1] - r[3], width: r[2], height: r[3]))
                }
            }
        }
    }
    controller.run()
    app.run()

default:
    exit(2)
}
