import AppKit
import Foundation

struct StatusPayload: Decodable {
    let student_id: String
    let capture_count: Int
    let current_time: String
    let mode: String
}

final class StatusBarController: NSObject, NSApplicationDelegate {
    private let statusFilePath: String
    private let window = NSWindow()
    private let label = NSTextField(labelWithString: "")
    private var timer: Timer?
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    init(statusFilePath: String) {
        self.statusFilePath = statusFilePath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        setupWindow()
        refreshStatus()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    private func setupWindow() {
        let initialFrame = calculateWindowFrame()
        window.setFrame(initialFrame, display: true)
        window.styleMask = [.borderless]
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.92)
        window.hasShadow = true
        window.ignoresMouseEvents = false

        label.frame = window.contentView?.bounds.insetBy(dx: 24, dy: 8) ?? .zero
        label.autoresizingMask = [.width, .height]
        label.alignment = .center
        label.font = NSFont.boldSystemFont(ofSize: 30)
        label.textColor = .white

        window.contentView?.addSubview(label)
        window.orderFrontRegardless()
    }

    private func calculateWindowFrame() -> NSRect {
        let screen = NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let horizontalMargin: CGFloat = 24
        let topMargin: CGFloat = 8
        let windowHeight: CGFloat = 56
        let windowWidth = max(visibleFrame.width - (horizontalMargin * 2), 520)
        let originX = visibleFrame.minX + ((visibleFrame.width - windowWidth) / 2)
        let originY = visibleFrame.maxY - windowHeight - topMargin

        return NSRect(x: originX, y: originY, width: windowWidth, height: windowHeight)
    }

    private func refreshStatus() {
        guard FileManager.default.fileExists(atPath: statusFilePath) else {
            NSApp.terminate(nil)
            return
        }

        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: statusFilePath)),
            let payload = try? JSONDecoder().decode(StatusPayload.self, from: data)
        else {
            return
        }

        window.setFrame(calculateWindowFrame(), display: true)

        let nowText = timeFormatter.string(from: Date())
        label.stringValue = "学籍番号: \(payload.student_id)    枚数: \(payload.capture_count)枚    時刻: \(nowText)"

        if payload.mode == "warning" {
            window.backgroundColor = NSColor.systemRed.withAlphaComponent(0.92)
            label.textColor = .white
        } else {
            window.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.92)
            label.textColor = .white
        }

        window.orderFrontRegardless()
    }
}

let statusFilePath: String
if CommandLine.arguments.count > 1 {
    statusFilePath = CommandLine.arguments[1]
} else {
    statusFilePath = "/tmp/CaptureSystem_status.json"
}

let app = NSApplication.shared
let delegate = StatusBarController(statusFilePath: statusFilePath)
app.delegate = delegate
app.run()
