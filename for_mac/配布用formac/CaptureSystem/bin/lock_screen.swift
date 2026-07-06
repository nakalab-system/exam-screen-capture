import AppKit
import Foundation

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum UnlockMode {
    case usb(policyFilePath: String)
}

struct UsbUnlockPolicy {
    let challengeId: String
    let requiredKeyFilename: String
    let keyHash: String
}

enum UsbKeyValidationResult {
    case success(pinHash: String)
    case usbNotFound
    case keyMismatch
    case pinHashMissing
}

final class HoldButton: NSButton {
    var onPressStart: (() -> Void)?
    var onPressEnd: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onPressStart?()
        super.mouseDown(with: event)
        onPressEnd?()
    }
}

final class LockScreenController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    private let mode: UnlockMode
    private let lockFlagPath: String

    private let window = KeyableWindow()
    private let statusLabel = NSTextField(labelWithString: "")
    private let passwordField = NSSecureTextField(frame: .zero)
    private let unlockButton = NSButton(frame: .zero)
    private let peekButton = HoldButton(frame: .zero)

    private var monitorTimer: Timer?
    private var unlockResult = false

    init(mode: UnlockMode, lockFlagPath: String) {
        self.mode = mode
        self.lockFlagPath = lockFlagPath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupWindow()
        setupContent()
        startMonitoring()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.window.makeKeyAndOrderFront(nil)
            self.window.makeFirstResponder(self.passwordField)
            self.passwordField.selectText(nil)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        false
    }

    @objc private func attemptUnlock() {
        if testInternetConnectivity() {
            statusLabel.stringValue = "状態: Wi-Fiをオフにしてから解除してください"
            statusLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.55, alpha: 1.0)
            window.alphaValue = 1.0
            window.makeFirstResponder(passwordField)
            return
        }

        switch mode {
        case .usb(let policyFilePath):
            guard let policy = loadUsbUnlockPolicy(from: policyFilePath) else {
                statusLabel.stringValue = "状態: USB解除設定の読込に失敗しました"
                statusLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.86, alpha: 1.0)
                return
            }

            switch validateUsbKey(with: policy) {
            case .usbNotFound:
                statusLabel.stringValue = "状態: TA用USBまたは鍵ファイルが見つかりません"
                statusLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.55, alpha: 1.0)
                passwordField.stringValue = ""
                window.makeFirstResponder(passwordField)
                return
            case .keyMismatch:
                statusLabel.stringValue = "状態: TA用USBの鍵が一致しません"
                statusLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.86, alpha: 1.0)
                passwordField.stringValue = ""
                window.makeFirstResponder(passwordField)
                return
            case .pinHashMissing:
                statusLabel.stringValue = "状態: TA用USB内の PIN 設定が見つかりません"
                statusLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.86, alpha: 1.0)
                passwordField.stringValue = ""
                window.makeFirstResponder(passwordField)
                return
            case .success(let pinHash):
                let inputHash = sha256(passwordField.stringValue)
                if inputHash == pinHash {
                    unlockResult = true
                    NSApp.stop(nil)
                    window.orderOut(nil)
                    return
                }

                statusLabel.stringValue = "状態: 解除失敗（TA用PINが正しくありません）"
                statusLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.86, alpha: 1.0)
                passwordField.stringValue = ""
                window.alphaValue = 1.0
                window.makeFirstResponder(passwordField)
                return
            }
        }
    }

    @objc private func monitorLockFlag() {
        if !FileManager.default.fileExists(atPath: lockFlagPath) {
            unlockResult = false
            NSApp.stop(nil)
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    private func setupWindow() {
        let width: CGFloat = 980
        let height: CGFloat = 600
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(
            x: screen.midX - (width / 2),
            y: screen.midY - (height / 2),
            width: width,
            height: height
        )

        window.setFrame(frame, display: true)
        window.styleMask = [.borderless]
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = NSColor(calibratedRed: 0.36, green: 0.02, blue: 0.04, alpha: 0.97)
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovable = false
        window.delegate = self
        window.acceptsMouseMovedEvents = true

        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 18
        window.contentView?.layer?.masksToBounds = true
        window.contentView?.layer?.borderWidth = 3
        window.contentView?.layer?.borderColor = NSColor.systemYellow.withAlphaComponent(0.75).cgColor
    }

    private func setupContent() {
        guard let contentView = window.contentView else { return }
        let isUsbMode: Bool
        switch mode {
        case .usb:
            isUsbMode = true
        }

        let iconView = NSImageView(frame: NSRect(x: 48, y: 500, width: 78, height: 78))
        iconView.image = NSImage(named: NSImage.cautionName)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "【警告】インターネット接続を検知しました")
        titleLabel.frame = NSRect(x: 142, y: 520, width: 790, height: 42)
        titleLabel.font = .boldSystemFont(ofSize: 31)
        titleLabel.textColor = .systemYellow
        contentView.addSubview(titleLabel)

        let studentLabel = NSTextField(labelWithString: "ただちにTA（試験監督）を呼んでください。\n※TAが到着するまで、PCには一切触れないでください。")
        studentLabel.frame = NSRect(x: 48, y: 404, width: 880, height: 88)
        studentLabel.font = .boldSystemFont(ofSize: 22)
        studentLabel.textColor = .white
        studentLabel.lineBreakMode = .byWordWrapping
        studentLabel.maximumNumberOfLines = 2
        contentView.addSubview(studentLabel)

        let guideLabel = NSTextField(labelWithString: "【TA用操作ガイド】\n・背景透過ボタンを長押しすると、背後の画面状況を確認できます。\n・Wi-Fi切断後に、TA用パスワードで解除してください。")
        guideLabel.frame = NSRect(x: 50, y: 290, width: 880, height: 88)
        guideLabel.font = .systemFont(ofSize: 18, weight: .medium)
        guideLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.68, alpha: 1.0)
        guideLabel.lineBreakMode = .byWordWrapping
        guideLabel.maximumNumberOfLines = 3
        guideLabel.stringValue = "【TA用操作ガイド】\n・背景透過ボタンを長押しすると、背後の画面状況を確認できます。\n・Wi-Fi切断後に、TA用USBを接続し、TA用PINで解除してください。"
        contentView.addSubview(guideLabel)

        statusLabel.frame = NSRect(x: 50, y: 220, width: 880, height: 28)
        statusLabel.font = .systemFont(ofSize: 18, weight: .medium)
        statusLabel.textColor = NSColor(calibratedWhite: 0.86, alpha: 1.0)
        statusLabel.stringValue = "状態: TA用USB + PIN待機中"
        contentView.addSubview(statusLabel)

        let pinLabel = NSTextField(labelWithString: isUsbMode ? "PIN :" : "PIN :")
        pinLabel.frame = NSRect(x: 50, y: 146, width: 160, height: 34)
        pinLabel.font = .boldSystemFont(ofSize: 22)
        pinLabel.textColor = .white
        contentView.addSubview(pinLabel)

        passwordField.frame = NSRect(x: 210, y: 140, width: 300, height: 42)
        passwordField.font = .systemFont(ofSize: 22)
        passwordField.focusRingType = .default
        passwordField.delegate = self
        contentView.addSubview(passwordField)

        unlockButton.frame = NSRect(x: 540, y: 138, width: 180, height: 46)
        unlockButton.title = "TA解除を実行"
        unlockButton.font = .boldSystemFont(ofSize: 18)
        unlockButton.bezelStyle = .rounded
        unlockButton.isBordered = false
        unlockButton.wantsLayer = true
        unlockButton.layer?.backgroundColor = NSColor.white.cgColor
        unlockButton.layer?.cornerRadius = 10
        unlockButton.contentTintColor = .black
        unlockButton.target = self
        unlockButton.action = #selector(attemptUnlock)
        contentView.addSubview(unlockButton)

        peekButton.frame = NSRect(x: 746, y: 138, width: 180, height: 46)
        peekButton.title = "背景透過"
        peekButton.font = .boldSystemFont(ofSize: 18)
        peekButton.bezelStyle = .rounded
        peekButton.isBordered = false
        peekButton.wantsLayer = true
        peekButton.layer?.backgroundColor = NSColor.darkGray.cgColor
        peekButton.layer?.cornerRadius = 10
        peekButton.contentTintColor = .white
        peekButton.onPressStart = { [weak self] in
            self?.window.alphaValue = 0.14
        }
        peekButton.onPressEnd = { [weak self] in
            self?.window.alphaValue = 1.0
        }
        contentView.addSubview(peekButton)

        DispatchQueue.main.async {
            self.window.makeFirstResponder(self.passwordField)
            self.passwordField.selectText(nil)
        }
    }

    private func startMonitoring() {
        monitorTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(monitorLockFlag), userInfo: nil, repeats: true)
    }

    private func loadUsbUnlockPolicy(from policyFilePath: String) -> UsbUnlockPolicy? {
        let challengeId = readKeyValue(from: policyFilePath, keyName: "challenge_id")
        let requiredKeyFilename = readKeyValue(from: policyFilePath, keyName: "required_key_filename")
        let keyHash = readKeyValue(from: policyFilePath, keyName: "key_hash")

        guard
            let challengeId,
            let requiredKeyFilename,
            let keyHash,
            !challengeId.isEmpty,
            !requiredKeyFilename.isEmpty,
            !keyHash.isEmpty
        else {
            return nil
        }

        return UsbUnlockPolicy(
            challengeId: challengeId,
            requiredKeyFilename: requiredKeyFilename,
            keyHash: keyHash
        )
    }

    private func validateUsbKey(with policy: UsbUnlockPolicy) -> UsbKeyValidationResult {
        let volumesURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        guard let volumeURLs = try? FileManager.default.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: nil) else {
            return .usbNotFound
        }

        var foundCandidate = false

        for volumeURL in volumeURLs {
            let keyURL = volumeURL.appendingPathComponent(policy.requiredKeyFilename)
            guard FileManager.default.fileExists(atPath: keyURL.path) else {
                continue
            }

            foundCandidate = true

            guard
                let challengeId = readKeyValue(from: keyURL.path, keyName: "challenge_id"),
                let unlockKey = readKeyValue(from: keyURL.path, keyName: "unlock_key")
            else {
                continue
            }

            guard challengeId == policy.challengeId else {
                continue
            }

            let computedKeyHash = sha256(unlockKey)
            if computedKeyHash == policy.keyHash {
                guard
                    let pinHash = readKeyValue(from: keyURL.path, keyName: "pin_hash"),
                    !pinHash.isEmpty
                else {
                    return .pinHashMissing
                }
                return .success(pinHash: pinHash)
            }
        }

        return foundCandidate ? .keyMismatch : .usbNotFound
    }

    private func readKeyValue(from filePath: String, keyName: String) -> String? {
        guard let contents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return nil
        }

        for line in contents.components(separatedBy: .newlines) {
            guard let separatorIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<separatorIndex])
            guard key == keyName else {
                continue
            }

            let valueStartIndex = line.index(after: separatorIndex)
            return String(line[valueStartIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func sha256(_ value: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf %s \"$1\" | shasum -a 256 | awk '{print $1}'", "sh", value]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }

    private func testInternetConnectivity() -> Bool {
        let checks = [
            ["/sbin/ping", "-c", "1", "-W", "1000", "8.8.8.8"],
            ["/usr/bin/dscacheutil", "-q", "host", "-a", "name", "www.google.com"],
            ["/usr/bin/curl", "-s", "-o", "/dev/null", "--max-time", "3", "http://clients3.google.com/generate_204"]
        ]

        let successCount = checks.reduce(0) { count, command in
            count + (runCommand(command) ? 1 : 0)
        }

        return successCount >= 2
    }

    private func runCommand(_ command: [String]) -> Bool {
        guard let executable = command.first else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func runResult() -> Int32 {
        app.run()
        return unlockResult ? 0 : 1
    }

    private var app: NSApplication {
        NSApplication.shared
    }
}

let modeArgument = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let lockFlagPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
let mode = UnlockMode.usb(policyFilePath: modeArgument)

let app = NSApplication.shared
let delegate = LockScreenController(mode: mode, lockFlagPath: lockFlagPath)
app.delegate = delegate
let result = delegate.runResult()
exit(result)
