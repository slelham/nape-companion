// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import Foundation

struct SeenInterface: Equatable {
    var vendorID: Int
    var productID: Int
    var productName: String?
    var primaryUsagePage: Int?
    var primaryUsage: Int?
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
        for (index, interface) in interfaces.enumerated() {
            if acceptsWired(interface) {
                return .open(index: index, transport: .wiredUSB)
            }
        }
        for (index, interface) in interfaces.enumerated() {
            if let name = attemptedReceiverName(interface) {
                return .open(
                    index: index,
                    transport: .receiverUnverified(productID: interface.productID, name: name)
                )
            }
        }
        return .idle
    }

    static func hexID(_ value: Int) -> String {
        String(format: "0x%04X", value)
    }

    private static func acceptsWired(_ interface: SeenInterface) -> Bool {
        interface.vendorID == NapeOpcode.vendorID
            && interface.productID == NapeOpcode.wiredProductID
            && isRawCollection(interface)
    }

    private static func attemptedReceiverName(_ interface: SeenInterface) -> String? {
        guard interface.vendorID == NapeOpcode.vendorID, isRawCollection(interface) else { return nil }
        return receivers.first { $0.attempted && $0.productID == interface.productID }?.name
    }

    private static func isRawCollection(_ interface: SeenInterface) -> Bool {
        interface.primaryUsagePage == NapeOpcode.rawUsagePage
            && interface.primaryUsage == NapeOpcode.rawUsage
    }
}
