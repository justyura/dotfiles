import Foundation
import Carbon

func updateInputSource() {
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = [NSHomeDirectory() + "/.config/sketchybar/plugins/input_source.sh"]
    do {
        try task.run()
    } catch {
        print("Failed to run update script: \(error)")
    }
}

DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name("AppleSelectedInputSourcesChangedNotification"),
    object: nil, queue: .main
) { _ in updateInputSource() }

DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    object: nil, queue: .main
) { _ in updateInputSource() }

updateInputSource()
RunLoop.main.run()
