// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import Foundation

struct UsagePair: Equatable {
    var page: Int
    var usage: Int
}

struct SeenInterface: Equatable {
    var vendorID: Int
    var productID: Int
    var productName: String?
    var primaryUsagePage: Int?
    var primaryUsage: Int?
    /// Other collections advertised on the same HID device. Not a reason to open it.
    var usagePairs: [UsagePair] = []
    /// IOKit transport string such as "USB" or "BluetoothLowEnergy". Nil when unread.
    var transport: String? = nil
}

enum Discovery: Equatable {
    case absent
    case open(index: Int, transport: TransportKind)
    case blocked(String)
}

struct HIDMatch: Equatable {
    var vendorID: Int
    var productID: Int
    var usagePage: Int
    var usage: Int
}

enum TransportKind: Equatable {
    case wiredUSB
    case receiverUnverified(productID: Int, name: String)
}

enum DeviceChoice: Equatable {
    case open(index: Int, transport: TransportKind)
    case idle
}

struct ReceiverRecord: Equatable {
    var productID: Int
    var name: String
    /// True only when this app will open the device, and only if it also
    /// exposes RAW HID usage page 0xFF60 usage 0x61.
    var attempted: Bool
    var note: String
}

enum NapeIdentity {
    /// Receivers named in OpenMouse-Project/mouse-protocol `KEYCHRON_RECEIVERS`
    /// and the Nape product map (commit b62a1cce2b63698ac00595efdb0067ecd54e34a0).
    /// Only Link-KM and Link-KM Type C are in that file's Nape product map.
    /// None of the receiver pairings were confirmed on Nape Pro hardware here.
    static let receivers: [ReceiverRecord] = [
        ReceiverRecord(
            productID: 0xD024,
            name: "CANDYSIGN Link",
            attempted: false,
            note: "Listed as a Keychron receiver. Not part of the Nape RAW HID product map."
        ),
        ReceiverRecord(
            productID: 0xD026,
            name: "Keychron Link-KM",
            attempted: true,
            note: "Included in the OpenMouse Nape product map as a receiver. Opened only when the RAW HID collection is present. Not confirmed with a Nape Pro on the dongle."
        ),
        ReceiverRecord(
            productID: 0xD027,
            name: "Keychron Receiver",
            attempted: false,
            note: "Listed as a Keychron receiver. Not part of the Nape RAW HID product map."
        ),
        ReceiverRecord(
            productID: 0xD028,
            name: "Keychron Ultra-Link 8K",
            attempted: false,
            note: "Listed as a Keychron receiver. M-series 8K traffic uses a different collection."
        ),
        ReceiverRecord(
            productID: 0xD029,
            name: "Keychron Link-KM Type C",
            attempted: true,
            note: "Included in the OpenMouse Nape product map as a receiver. Opened only when the RAW HID collection is present. Not confirmed with a Nape Pro on the dongle."
        ),
        ReceiverRecord(
            productID: 0xD030,
            name: "Keychron Link Type A",
            attempted: false,
            note: "Listed as a Keychron receiver. Not part of the Nape RAW HID product map."
        ),
        ReceiverRecord(
            productID: 0xD031,
            name: "Keychron Link Type C",
            attempted: false,
            note: "Listed as a Keychron receiver. Not part of the Nape RAW HID product map."
        ),
        ReceiverRecord(
            productID: 0xD05A,
            name: "Keychron TurboLink 8K",
            attempted: false,
            note: "Listed as a Keychron receiver. Not part of the Nape RAW HID product map."
        ),
        ReceiverRecord(
            productID: 0xD05B,
            name: "Keychron 8K Nordic receiver",
            attempted: false,
            note: "OpenMouse lists this Ultra-Link-class id and says the pairing is not confirmed. It is not in the Nape product map."
        ),
        ReceiverRecord(
            productID: 0xD078,
            name: "Keychron 8K Nordic receiver",
            attempted: false,
            note: "OpenMouse lists this id next to G3 Air and says the pairing is not confirmed. It is not in the Nape product map."
        ),
    ]

    static func matches() -> [HIDMatch] {
        var rows = [
            HIDMatch(
                vendorID: NapeOpcode.vendorID,
                productID: NapeOpcode.wiredProductID,
                usagePage: NapeOpcode.rawUsagePage,
                usage: NapeOpcode.rawUsage
            ),
        ]
        for receiver in receivers where receiver.attempted {
            rows.append(HIDMatch(
                vendorID: NapeOpcode.vendorID,
                productID: receiver.productID,
                usagePage: NapeOpcode.rawUsagePage,
                usage: NapeOpcode.rawUsage
            ))
        }
        return rows
    }

    static func choose(_ interfaces: [SeenInterface]) -> DeviceChoice {
        switch classify(interfaces) {
        case .open(let index, let transport):
            return .open(index: index, transport: transport)
        case .absent, .blocked:
            return .idle
        }
    }

    /// Decides what the menu should say before any device is opened.
    /// Only a primary usage page 0xFF60 usage 0x61 on USB (or an unread transport)
    /// is `.open`. A mouse collection, a secondary vendor pair, or Bluetooth is `.blocked`.
    static func classify(_ interfaces: [SeenInterface]) -> Discovery {
        for (index, interface) in interfaces.enumerated() where acceptsWired(interface) {
            return .open(index: index, transport: .wiredUSB)
        }
        for (index, interface) in interfaces.enumerated() {
            if let name = attemptedReceiverName(interface) {
                return .open(
                    index: index,
                    transport: .receiverUnverified(productID: interface.productID, name: name)
                )
            }
        }
        if let message = blockage(for: interfaces) {
            return .blocked(message)
        }
        return .absent
    }

    static func isWatched(_ interface: SeenInterface) -> Bool {
        guard interface.vendorID == NapeOpcode.vendorID else { return false }
        if interface.productID == NapeOpcode.wiredProductID { return true }
        if receivers.contains(where: { $0.attempted && $0.productID == interface.productID }) {
            return true
        }
        if let name = interface.productName?.lowercased(), name.contains("nape") {
            return true
        }
        return false
    }

    static func isOpenableRaw(_ interface: SeenInterface) -> Bool {
        guard isRawCollection(interface), !isBluetooth(interface) else { return false }
        if acceptsWired(interface) { return true }
        return attemptedReceiverName(interface) != nil
    }

    /// Product ids and usage pages only. No serial number and no location id.
    static func diagnosticSummary(_ interfaces: [SeenInterface]) -> String {
        if interfaces.isEmpty { return "watched interfaces: none" }
        return interfaces.map { interface in
            "\(hexID(interface.vendorID)):\(hexID(interface.productID)) \(usageSummary(interface))"
        }.joined(separator: "; ")
    }

    static func hexID(_ value: Int) -> String {
        String(format: "0x%04X", value)
    }

    private static func acceptsWired(_ interface: SeenInterface) -> Bool {
        interface.vendorID == NapeOpcode.vendorID
            && interface.productID == NapeOpcode.wiredProductID
            && isRawCollection(interface)
            && !isBluetooth(interface)
    }

    private static func attemptedReceiverName(_ interface: SeenInterface) -> String? {
        guard interface.vendorID == NapeOpcode.vendorID,
              isRawCollection(interface),
              !isBluetooth(interface)
        else { return nil }
        return receivers.first { $0.attempted && $0.productID == interface.productID }?.name
    }

    private static func isRawCollection(_ interface: SeenInterface) -> Bool {
        interface.primaryUsagePage == NapeOpcode.rawUsagePage
            && interface.primaryUsage == NapeOpcode.rawUsage
    }

    private static func isBluetooth(_ interface: SeenInterface) -> Bool {
        guard let transport = interface.transport?.lowercased() else { return false }
        return transport.contains("bluetooth")
    }

    private static func hasSecondaryRaw(_ interface: SeenInterface) -> Bool {
        guard !isRawCollection(interface) else { return false }
        return interface.usagePairs.contains {
            $0.page == NapeOpcode.rawUsagePage && $0.usage == NapeOpcode.rawUsage
        }
    }

    private static func blockage(for interfaces: [SeenInterface]) -> String? {
        let watched = interfaces.filter(isWatched)
        guard !watched.isEmpty else { return nil }
        var lines: [String] = []
        let productIDs = Set(watched.map(\.productID)).sorted()
        for productID in productIDs {
            let rows = watched.filter { $0.productID == productID }
            let name = rows.compactMap(\.productName).first { !$0.isEmpty }
            let transports = Set(rows.compactMap(\.transport)).sorted()
            var line = "Product \(hexID(productID))"
            if let name { line += " (\(name))" }
            if !transports.isEmpty { line += " via \(transports.joined(separator: ", "))" }
            let collections = rows.map(usageSummary).joined(separator: "; ")
            line += " is visible. Collections: \(collections)."
            lines.append(line)
        }
        if watched.allSatisfy(isBluetooth) {
            lines.append("Bluetooth is not opened. The documented path is wired USB.")
        } else if watched.contains(where: hasSecondaryRaw) {
            lines.append(
                "Usage page 0xFF60 usage 0x61 is not the primary collection, so this app did not open the interface and is not reading mouse reports."
            )
        } else if !watched.contains(where: isRawCollection) {
            lines.append("None of these collections is primary usage page 0xFF60 usage 0x61, so nothing was opened.")
        }
        lines.append(
            "Keychron Launcher uses its own HID claim and can work while this app has no config interface. Quit Launcher and replug USB to try again. Mouse and keyboard collections were not opened."
        )
        return lines.joined(separator: "\n")
    }

    private static func usageSummary(_ interface: SeenInterface) -> String {
        var parts: [String] = []
        if let page = interface.primaryUsagePage, let usage = interface.primaryUsage {
            parts.append("primary \(hexID(page))/\(hexID(usage))")
        } else {
            parts.append("primary usage unread")
        }
        for pair in interface.usagePairs {
            let text = "\(hexID(pair.page))/\(hexID(pair.usage))"
            if !parts.contains(where: { $0.contains(text) }) {
                parts.append(text)
            }
        }
        return parts.joined(separator: " ")
    }
}
