// agent_hud：option+a 会话切换器的按键监听（界面是 sketchybar 的 agent 会话面板，本程序不开窗口）
//
//   agent_hud <面板脚本> <跳转脚本> <序列文件> <选中行号文件> <pid 文件>
//
// - 按住 option 超过 0.2 秒：执行 <面板脚本> switcher_show，在 bar 下方显示会话面板
// - 松开 option：若面板已显示则先执行 <面板脚本> switcher_hide，再执行 <跳转脚本> <选中行的状态文件>，然后退出
// - 选中行号由 agent_switch.sh 在每次按 a 时改写（它同时负责移动面板高亮）
//
// 编译：swiftc -O agent_hud.swift -o agent_hud（agent_switch.sh 会在需要时自动编译）

import CoreGraphics
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 5 else { exit(2) }
let (popupScript, jumpScript, sequenceFile, selectedFile, pidFile) = (args[0], args[1], args[2], args[3], args[4])
try? String(ProcessInfo.processInfo.processIdentifier).write(toFile: pidFile, atomically: true, encoding: .utf8)

func run(_ path: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    try? process.run()
    process.waitUntilExit()
}

func read(_ path: String) -> String {
    (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
}

let started = Date()
var shown = false

while CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate) {
    if !shown && Date().timeIntervalSince(started) > 0.2 {
        shown = true
        run(popupScript, ["switcher_show"])
    }
    if Date().timeIntervalSince(started) > 30 { break }
    usleep(20_000)
}

let lines = read(sequenceFile).split(separator: "\n").map(String.init)
let selected = Int(read(selectedFile).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
for path in [selectedFile, pidFile] { try? FileManager.default.removeItem(atPath: path) }

if shown { run(popupScript, ["switcher_hide"]) }
if selected >= 1 && selected <= lines.count, let file = lines[selected - 1].split(separator: "\t").first {
    run(jumpScript, [String(file)])
}
