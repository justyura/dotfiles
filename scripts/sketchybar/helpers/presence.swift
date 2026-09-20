import AppKit
import AVFoundation
import Vision
import CoreGraphics

let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/sketchybar")
try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
let resultURL = cache.appendingPathComponent("presence.json")
func activity() -> [String: Any] {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
    return ["idle": CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!),
            "locked": (session["CGSSessionScreenIsLocked"] as? Bool ?? false) ||
                      !(session["kCGSessionOnConsoleKey"] as? Bool ?? true)]
}
func writeResult(_ status: String) {
    let data: [String: Any] = ["status": status, "at": Date().timeIntervalSince1970]
    if let json = try? JSONSerialization.data(withJSONObject: data) { try? json.write(to: resultURL, options: .atomic) }
}

if CommandLine.arguments.contains("--idle") {
    let data = try! JSONSerialization.data(withJSONObject: activity())
    print(String(data: data, encoding: .utf8)!)
    exit(0)
}

final class Probe: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "local.presence.capture")
    var finished = false
    var frames = 0
    var lastFrame = Date.distantPast
    func finish(_ status: String) {
        guard !finished else { return }
        finished = true
        session.stopRunning()
        writeResult(status)
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
    func start() {
        queue.async {
            guard !(activity()["locked"] as? Bool ?? true) else { self.finish("locked"); return }
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                self.finish("permission"); return
            }
            guard let device = AVCaptureDevice.default(for: .video) else { self.finish("unavailable"); return }
            guard !device.isInUseByAnotherApplication else { self.finish("busy"); return }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.queue)
                self.session.beginConfiguration()
                self.session.sessionPreset = .low
                guard self.session.canAddInput(input), self.session.canAddOutput(output) else {
                    self.session.commitConfiguration(); self.finish("unavailable"); return
                }
                self.session.addInput(input)
                self.session.addOutput(output)
                self.session.commitConfiguration()
                self.session.startRunning()
                self.queue.asyncAfter(deadline: .now() + 4) { self.finish("unknown") }
            } catch { self.finish("unavailable") }
        }
        // Bound the process lifetime even when camera startup stalls.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            writeResult("timeout")
            exit(0)
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !finished, Date().timeIntervalSince(lastFrame) > 0.4,
              let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if activity()["locked"] as? Bool == true { finish("locked"); return }
        lastFrame = Date()
        let faces = VNDetectFaceRectanglesRequest()
        let people = VNDetectHumanRectanglesRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixel, options: [:]).perform([faces, people])
            if (faces.results ?? []).contains(where: { $0.confidence >= 0.5 }) ||
               (people.results ?? []).contains(where: { $0.confidence >= 0.5 }) {
                finish("present"); return
            }
            frames += 1
            if frames >= 3 { finish("absent") }
        } catch { finish("unknown") }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let probe = Probe()
if CommandLine.arguments.contains("--authorize") {
    AVCaptureDevice.requestAccess(for: .video) { allowed in
        writeResult(allowed ? "authorized" : "permission")
        DispatchQueue.main.async { app.terminate(nil) }
    }
} else { probe.start() }
app.run()
