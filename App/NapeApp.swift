// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import AppKit

/// Keep this aligned with CFBundleShortVersionString in build.sh.
enum AppMetadata {
    static let version = "0.1.0"
    static let bundleIdentifier = "local.slelham.nape-companion"
}

@main
enum NapeApp {
    private static var retained: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retained = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, HIDMonitorDelegate {
    private let monitor = HIDMonitor()
    private var engine: CompanionEngine
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var timer: Timer?
    private var syncing = false
    private let debugLog = ProcessInfo.processInfo.environment["NAPE_COMPANION_DEBUG"] == "1"

    override init() {
        engine = CompanionEngine(names: LayerNames.load(from: UserDefaults.standard))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.autoenablesItems = false
        menu.delegate = self
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = menu
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        statusItem = item
        monitor.delegate = self
        monitor.start()
        timer = Timer.scheduledTimer(
            timeInterval: PollTiming.interval,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        refreshTitle(at: Date())
        syncDevices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        monitor.suspend()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(at: Date())
    }

    func hidMonitorInterfacesChanged() {
        syncDevices()
    }

    func hidMonitorReceived(bytes: [UInt8], reportID: UInt32) {
        let now = Date()
        logReport(bytes)
        engine.receive(bytes: bytes, reportID: reportID, at: now)
        if let packet = engine.tick(at: now) {
            send(packet, at: now)
        }
        refreshTitle(at: now)
    }

    @objc private func timerFired() {
        let now = Date()
        monitor.refreshDeviceList()
        if monitor.openedIndex == nil, engine.readyToOpen(at: now) {
            syncDevices()
        }
        if let packet = engine.tick(at: now) {
            send(packet, at: now)
        }
        refreshTitle(at: now)
    }

    @objc private func willSleep() {
        engine.sleep()
        monitor.suspend()
        refreshTitle(at: Date())
    }

    @objc private func didWake() {
        engine.noteWake()
        monitor.resume()
        syncDevices()
        refreshTitle(at: Date())
    }

    @objc private func rename(_ sender: Any?) {
        RenamePanel.show(names: engine.names) { [weak self] names in
            guard let self else { return }
            LayerNames.save(names, to: self.defaults)
            self.engine.replaceNames(names)
            self.refreshTitle(at: Date())
        }
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func syncDevices() {
        dispatchPrecondition(condition: .onQueue(.main))
        if syncing { return }
        syncing = true
        defer { syncing = false }
        let now = Date()
        engine.interfacesChanged(monitor.interfaces)
        guard let index = engine.desiredDeviceIndex else {
            monitor.close()
            refreshTitle(at: now)
            return
        }
        if monitor.openedIndex == index {
            refreshTitle(at: now)
            return
        }
        monitor.close()
        let result = monitor.open(index: index)
        if result == HIDResult.success {
            if let packet = engine.connectionOpened(at: now) {
                send(packet, at: now)
            }
        } else {
            engine.openFailed(ioReturn: result, at: now)
        }
        refreshTitle(at: now)
    }

    private func send(_ packet: [UInt8], at now: Date) {
        logReport(packet)
        let result = monitor.setReport(packet)
        guard result == HIDResult.success else {
            engine.sendFailed(ioReturn: result, at: now)
            refreshTitle(at: now)
            return
        }
    }

    private func refreshTitle(at now: Date) {
        let presentation = engine.presentation(at: now)
        statusItem?.button?.title = presentation.title
        statusItem?.button?.setAccessibilityLabel(presentation.accessibilityLabel)
        statusItem?.button?.toolTip = presentation.accessibilityLabel
    }

    private func rebuildMenu(at now: Date) {
        let presentation = engine.presentation(at: now)
        menu.removeAllItems()
        let version = NSMenuItem(title: "Nape Companion \(AppMetadata.version)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())
        for entry in presentation.entries {
            switch entry {
            case .info(let text):
                let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            case .separator:
                menu.addItem(.separator())
            case .rename:
                menu.addItem(NSMenuItem(
                    title: "Layer names…",
                    action: #selector(rename(_:)),
                    keyEquivalent: ""
                ))
                menu.items.last?.target = self
            case .quit:
                let item = NSMenuItem(
                    title: "Quit Nape Companion",
                    action: #selector(quit(_:)),
                    keyEquivalent: "q"
                )
                item.target = self
                menu.addItem(item)
            }
        }
        refreshTitle(at: now)
    }

    private func logReport(_ bytes: [UInt8]) {
        guard debugLog else { return }
        let head = bytes.prefix(4).map { String(format: "%02X", $0) }.joined(separator: " ")
        let line = "nape-companion \(head)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
