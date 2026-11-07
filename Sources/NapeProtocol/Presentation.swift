// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import Foundation

enum MenuEntry: Equatable {
    case info(String)
    case rename
    case quit
    case separator
}

struct MenuPresentation: Equatable {
    var title: String
    var accessibilityLabel: String
    var isLive: Bool
    var entries: [MenuEntry]

    static func make(phase: Phase, names: [String], now: Date) -> MenuPresentation {
        switch phase {
        case .disconnected(let detail):
            return disconnected(detail)
        case .connecting(let transport):
            return connecting(transport)
        case .live(let reading):
            return live(reading, names: names, now: now)
        case .failed(let failure):
            return failed(failure, names: names)
        }
    }

    private static func disconnected(_ detail: DisconnectDetail) -> MenuPresentation {
        let line: String
        let label: String
        switch detail {
        case .nothingAttached:
            line = "No HID interface for vendor 0x3434 product 0x0440 was found."
            label = "Disconnected. No Nape Pro HID interface was found."
        case .asleep:
            line = "The Mac is asleep. No layer is shown as live."
            label = "Asleep. No layer is shown as live."
        case .removed:
            line = "The trackball was unplugged. No layer is shown as live."
            label = "Unplugged. No layer is shown as live."
        }
        return MenuPresentation(
            title: "–",
            accessibilityLabel: label,
            isLive: false,
            entries: [
                .info(line),
                .info("Plug in with USB. If it is already plugged in, macOS is not showing product 0x0440 or a device name containing Nape. Bluetooth is not supported."),
                .separator,
                .rename,
                .separator,
                .quit,
            ]
        )
    }

    private static func connecting(_ transport: TransportKind) -> MenuPresentation {
        let line = "Connecting. \(transport.summary)"
        return MenuPresentation(
            title: "…",
            accessibilityLabel: "Connecting to the Nape Pro. Waiting for a layer reply.",
            isLive: false,
            entries: [
                .info(line),
                .info("Waiting for a layer reply. Nothing is shown as live yet."),
                .separator,
                .rename,
                .separator,
                .quit,
            ]
        )
    }

    private static func live(_ reading: ActiveReading, names: [String], now: Date) -> MenuPresentation {
        let name = LayerNames.menuName(displayLayer: reading.displayLayer, names: names)
        let title = LayerNames.statusTitle(displayLayer: reading.displayLayer, names: names)
        var entries: [MenuEntry] = [
            .info("Live"),
            .info("Layer \(reading.displayLayer) · \(name)"),
            .info(orientationLine(reading)),
            .info(reading.transport.summary),
        ]
        if let firmware = reading.firmwareText, !firmware.isEmpty {
            entries.append(.info("Firmware \(firmware)"))
        }
        if let via = viaLine(reading.viaLayerCount) {
            entries.append(.info(via))
        }
        entries.append(.info(confirmedLine(reading: reading, now: now)))
        entries.append(.separator)
        entries.append(.rename)
        entries.append(.separator)
        entries.append(.quit)
        let orientation = orientationSpoken(reading)
        return MenuPresentation(
            title: title,
            accessibilityLabel: "Live. Layer \(reading.displayLayer), \(name). \(orientation) \(reading.transport.spoken)",
            isLive: true,
            entries: entries
        )
    }

    private static func failed(_ failure: FailureState, names: [String]) -> MenuPresentation {
        var entries: [MenuEntry] = [.info("Not live")]
        for line in failure.message.split(separator: "\n", omittingEmptySubsequences: true) {
            entries.append(.info(String(line)))
        }
        if let last = failure.lastConfirmed {
            let name = LayerNames.menuName(displayLayer: last.displayLayer, names: names)
            entries.append(.info(
                "Last confirmed reading is not live: Layer \(last.displayLayer) · \(name)."
            ))
        }
        if let transport = failure.transport {
            entries.append(.info(transport.summary))
        }
        entries.append(contentsOf: [.separator, .rename, .separator, .quit])
        return MenuPresentation(
            title: "!",
            accessibilityLabel: "Not live. \(failure.message)",
            isLive: false,
            entries: entries
        )
    }

    private static func orientationLine(_ reading: ActiveReading) -> String {
        switch (reading.liveOrientation, reading.storedOrientation) {
        case (let live?, let stored?) where live.degrees == stored.degrees:
            return "OctaShift \(live.degrees)°"
        case (let live?, let stored?):
            return "OctaShift \(live.degrees)° live, \(stored.degrees)° stored on this layer"
        case (let live?, nil):
            return "OctaShift \(live.degrees)°"
        case (nil, let stored?):
            return "OctaShift \(stored.degrees)° stored on this layer. The live angle was not read."
        case (nil, nil):
            if let note = reading.orientationNote {
                return "OctaShift angle was not read. \(note)"
            }
            return "OctaShift angle was not read."
        }
    }

    private static func orientationSpoken(_ reading: ActiveReading) -> String {
        if let live = reading.liveOrientation {
            return "OctaShift \(live.degrees) degrees."
        }
        return "OctaShift angle was not read."
    }

    private static func viaLine(_ count: Int?) -> String? {
        guard let count else { return nil }
        if count == 9 {
            return "VIA layer count 9. Firmware indexes 1–8 are shown as layers 0–7. Index 0 is the documented spare slot."
        }
        if count == 8 {
            return "VIA layer count 8."
        }
        return "VIA layer count \(count). Labels 0–7 assume firmware indexes 1–8. This count is outside that pair."
    }

    private static func confirmedLine(reading: ActiveReading, now: Date) -> String {
        let age = now.timeIntervalSince(reading.confirmedAt)
        if age < 1 {
            return "Confirmed just now."
        }
        return "Confirmed \(Int(age))s ago."
    }
}

extension TransportKind {
    var summary: String {
        switch self {
        case .wiredUSB:
            return "Wired USB, product \(NapeIdentity.hexID(NapeOpcode.wiredProductID)). Documented path."
        case .receiverUnverified(let productID, let name):
            return "\(name), product \(NapeIdentity.hexID(productID)). Unverified 2.4 GHz path. The same read-only RAW HID queries as USB were used. Confirm the layer on the device."
        }
    }

    var spoken: String {
        switch self {
        case .wiredUSB:
            return "Wired USB."
        case .receiverUnverified(_, let name):
            return "\(name), unverified receiver path."
        }
    }
}
