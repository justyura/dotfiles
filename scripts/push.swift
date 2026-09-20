#!/usr/bin/env swift
import CoreGraphics
import Foundation

// 从屏幕中下部开始，持续往下推
let startX: CGFloat = 700
let startY: CGFloat = 800
let steps = 80
let stepSize: CGFloat = 15
let delayUs: UInt32 = 8000  // 每步间隔 8ms

for i in 1...steps {
    let y = startY + CGFloat(i) * stepSize
    let point = CGPoint(x: startX, y: y)
    let source = CGEventSource(stateID: .hidSystemState)
guard let event = CGEvent(
    mouseEventSource: source,
    mouseType: .mouseMoved,
    mouseCursorPosition: point,
    mouseButton: .left
) else { continue }
    
    
    // 关键：显式设置 delta，push-through 检测需要
    event.setIntegerValueField(.mouseEventDeltaX, value: 0)
    event.setIntegerValueField(.mouseEventDeltaY, value: Int64(stepSize))
    event.post(tap: .cghidEventTap)
    
    usleep(delayUs)
}
