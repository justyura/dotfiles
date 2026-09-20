import AppKit

guard CommandLine.arguments.count == 6 || CommandLine.arguments.count == 7 else { exit(1) }

let output = CommandLine.arguments[1]
let five = max(-1, min(100, Int(CommandLine.arguments[2]) ?? -1))
let week = max(-1, min(100, Int(CommandLine.arguments[3]) ?? -1))
let mode = CommandLine.arguments.count == 7 ? CommandLine.arguments[6] : "dual"

func color(_ value: String) -> NSColor {
    let hex = String(value.suffix(6))
    let number = UInt64(hex, radix: 16) ?? 0x737aa2
    return NSColor(
        red: CGFloat((number >> 16) & 0xff) / 255,
        green: CGFloat((number >> 8) & 0xff) / 255,
        blue: CGFloat(number & 0xff) / 255,
        alpha: 1
    )
}

let fiveColor = color(CommandLine.arguments[4])
let weekColor = color(CommandLine.arguments[5])
let width = 108
let height = 104

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(1) }

bitmap.size = NSSize(width: width, height: height)
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

let trackColor = color("2c3240")

func drawBar(x: CGFloat, percentage: Int, fillColor: NSColor, title: String) {
    let y: CGFloat = 10
    let barWidth: CGFloat = 36
    let barHeight: CGFloat = 68
    let radius: CGFloat = 9
    let track = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barWidth, height: barHeight),
                             xRadius: radius, yRadius: radius)

    trackColor.setFill()
    track.fill()

    let fillHeight = barHeight * CGFloat(max(0, percentage)) / 100
    if fillHeight > 0 {
        NSGraphicsContext.saveGraphicsState()
        track.addClip()
        fillColor.setFill()
        NSRect(x: x, y: y, width: barWidth, height: fillHeight).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: color("929baa")
    ]
    let text = NSAttributedString(string: title, attributes: attributes)
    let size = text.size()
    text.draw(at: NSPoint(x: x + (barWidth - size.width) / 2, y: 84))

    // 图片按 0.5 缩放显示，百分比保持 7.5pt，低饱和填充让项目区更突出。
    // 双色文字：压在彩色填充上的部分用深色，落在灰色轨道上的部分用白色，跨边界时各自裁剪。
    func percentageText(_ textColor: NSColor) -> NSAttributedString {
        NSAttributedString(string: percentage < 0 ? "–" : "\(percentage)%", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: percentage == 100 ? 13 : 15, weight: .bold),
            .foregroundColor: textColor
        ])
    }
    let numberSize = percentageText(.white).size()
    let origin = NSPoint(x: x + (barWidth - numberSize.width) / 2, y: y + (barHeight - numberSize.height) / 2)
    let fillTop = y + fillHeight
    let regions: [(NSRect, NSColor)] = [
        (NSRect(x: x, y: 0, width: barWidth, height: fillTop), color("1a1b26")),
        (NSRect(x: x, y: fillTop, width: barWidth, height: CGFloat(height) - fillTop), color("d1d7e0"))
    ]
    for (clip, textColor) in regions where clip.height > 0 {
        NSGraphicsContext.saveGraphicsState()
        clip.clip()
        percentageText(textColor).draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }
}

if mode == "week" {
    drawBar(x: 36, percentage: week, fillColor: weekColor, title: "7d")
} else {
    drawBar(x: 10, percentage: five, fillColor: fiveColor, title: "5h")
    drawBar(x: 62, percentage: week, fillColor: weekColor, title: "7d")
}

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: output))
