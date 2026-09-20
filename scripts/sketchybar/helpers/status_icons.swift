// status_icons：把 Nerd Font 字形渲染成居中的 64×64 PNG，给 sketchybar 当 background.image 用
// （agent 会话面板的一行只有 icon/label 两段文字，状态图标改成图片后 icon 才能单独用粗体显示项目名）
//
//   status_icons <输出目录> <名字> <字形> <颜色 0xAARRGGBB> [<名字> <字形> <颜色> ...]
//
// 输出 <输出目录>/<名字>.png；sketchybar 按 32pt 高度显示图片再乘以 image.scale
//
// 编译：swiftc -O status_icons.swift -o status_icons（agent_popup.sh 会在需要时自动编译）

import AppKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 4, (args.count - 1) % 3 == 0 else { exit(2) }
let outDir = URL(fileURLWithPath: args[0])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let size = 64
let font = NSFont(name: "HackNerdFont-Regular", size: 56) ?? NSFont.systemFont(ofSize: 56)

for i in stride(from: 1, to: args.count, by: 3) {
    let (name, glyph) = (args[i], args[i + 1])
    let argb = UInt32(args[i + 2].replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0xffffffff
    let color = NSColor(srgbRed: CGFloat((argb >> 16) & 0xff) / 255, green: CGFloat((argb >> 8) & 0xff) / 255,
                        blue: CGFloat(argb & 0xff) / 255, alpha: CGFloat((argb >> 24) & 0xff) / 255)

    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: color]))
    // 按字形实际轮廓居中（行高/基线会让字形偏上）
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    context.textPosition = CGPoint(x: CGFloat(size) / 2 - bounds.midX, y: CGFloat(size) / 2 - bounds.midY)
    CTLineDraw(line, context)

    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: outDir.appendingPathComponent("\(name).png"), options: .atomic)
}
