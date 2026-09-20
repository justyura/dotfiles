// input_source：sketchybar 输入法状态项的辅助程序
//
//   input_source                 输出当前系统输入法 id（如 im.rime.inputmethod.Squirrel.Hans / com.apple.keylayout.US）
//   input_source select <id>     切换到指定输入法
//   input_source tap-right-control   模拟单按右 Control（鼠须管里即切换中英，等同单按 🌐）
//
// 编译：swiftc -O input_source.swift -o input_source（plugins/input_method.sh 会在需要时自动编译）

import Carbon
import Foundation

func property(_ source: TISInputSource, _ key: CFString) -> String {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return "" }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case nil:
    print(property(TISCopyCurrentKeyboardInputSource().takeRetainedValue(), kTISPropertyInputSourceID))

case "select" where args.count == 2:
    let filter = [kTISPropertyInputSourceID: args[1]] as CFDictionary
    guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
          let source = sources.first else { exit(1) }
    exit(TISSelectInputSource(source) == noErr ? 0 : 1)

case "tap-right-control":
    let eventSource = CGEventSource(stateID: .hidSystemState)
    if let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 62, keyDown: true) {
        down.type = .flagsChanged
        down.flags = [.maskControl]
        down.post(tap: .cghidEventTap)
    }
    usleep(40_000)
    if let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 62, keyDown: false) {
        up.type = .flagsChanged
        up.flags = []
        up.post(tap: .cghidEventTap)
    }

default:
    exit(2)
}
