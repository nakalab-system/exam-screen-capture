import AppKit
import Foundation

struct StatusPayload: Decodable {
    let student_id: String
    let capture_count: Int
    let current_time: String
    let mode: String
}

final class StatusBarView: NSView {
    var displayText: String = ""
    var textColor: NSColor = .systemYellow
    var textFont: NSFont = .boldSystemFont(ofSize: 22)

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !displayText.isEmpty else {
            return
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        let textSize = (displayText as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: 16,
            y: (bounds.height - textSize.height) / 2 - 1,
            width: bounds.width - 32,
            height: textSize.height + 2
        )

        (displayText as NSString).draw(in: textRect, withAttributes: attributes)
    }
}

final class StatusBarController: NSObject, NSApplicationDelegate {
    private let statusFilePath: String
    private let window = NSWindow()
    private let statusView = StatusBarView()
    private var timer: Timer?
    private let normalAlpha: CGFloat = 0.78
    private let hoverAlpha: CGFloat = 0.18
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    init(statusFilePath: String) {
        self.statusFilePath = statusFilePath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        window.backgroundColor = NSColor.black.withAlphaComponent(0.94)
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.alphaValue = normalAlpha

        statusView.frame = window.contentView?.bounds ?? .zero
        statusView.autoresizingMask = [.width, .height]
        statusView.textFont = NSFont.boldSystemFont(ofSize: 22)
        statusView.textColor = .systemYellow

        window.contentView?.addSubview(statusView)
        window.orderFrontRegardless()
    }

    private func calculateWindowFrame(for text: String = "学籍番号: 00000000  枚数: 000枚  時刻: 00:00") -> NSRect {
        let screen = NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let horizontalMargin: CGFloat = 18
        let topMargin: CGFloat = 2
        let windowHeight: CGFloat = 36
        let textFont = NSFont.boldSystemFont(ofSize: 22)
        let textWidth = (text as NSString).size(withAttributes: [.font: textFont]).width
        let desiredWidth = ceil(textWidth) + 48
        let maxWidth = visibleFrame.width - (horizontalMargin * 2)
        let windowWidth = min(max(desiredWidth, 360), maxWidth)
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

        let nowText = timeFormatter.string(from: Date())
        let displayText = "学籍番号: \(payload.student_id)    枚数: \(payload.capture_count)枚    時刻: \(nowText)"
        statusView.displayText = displayText
        window.setFrame(calculateWindowFrame(for: displayText), display: true)

        if payload.mode == "warning" {
            window.backgroundColor = NSColor.systemRed.withAlphaComponent(0.88)
            statusView.textColor = .systemYellow
        } else {
            window.backgroundColor = NSColor.black.withAlphaComponent(0.94)
            statusView.textColor = .systemYellow
        }

        let mousePoint = NSEvent.mouseLocation
        let isHover = window.frame.contains(mousePoint)
        window.alphaValue = isHover ? hoverAlpha : normalAlpha
        statusView.needsDisplay = true
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
