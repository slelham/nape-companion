// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import Foundation

/// Read-only command bytes for the Keychron Nape Pro RAW HID interface.
///
/// Layout sources, neither of which is copied into this file:
/// dobachi, NapeProConfiguration `docs/nape-pro-hid-protocol.md`
/// (commit 1bca8c004c02e18bf41021da4116cb2955faed24, MIT).
/// OpenMouse-Project/mouse-protocol `src/keychron/index.ts`
/// (commit b62a1cce2b63698ac00595efdb0067ecd54e34a0, AGPL-3.0) for the
/// 0xA3 current-layer reply. See docs/protocol.md.
enum NapeOpcode {
    static let vendorID = 0x3434
    static let wiredProductID = 0x0440
    static let rawUsagePage = 0xFF60
    static let rawUsage = 0x61
    static let reportID: UInt8 = 0
    static let packetLength = 32
    static let userLayerCount = 8
    static let orientationSteps = 8
    static let orientationStepDegrees = 45

    static let getLayerCount: UInt8 = 0x11
    static let getFirmware: UInt8 = 0xA1
    static let getCurrentLayer: UInt8 = 0xA3
    static let miscGroup: UInt8 = 0xA7
    static let getOrientation: UInt8 = 0x20
    static let getLayerOrientation: UInt8 = 0x38
}

enum Query: Equatable {
    case firmware
    case layerCount
    case currentLayer
    case liveOrientation
    case storedOrientation(firmwareLayer: Int)
}

enum QueryPacket: Equatable {
    case ready([UInt8])
    case rejected(String)
}

enum NapeQuery {
    static func packet(for query: Query) -> QueryPacket {
        switch query {
        case .firmware:
            return .ready(frame([NapeOpcode.getFirmware]))
        case .layerCount:
            return .ready(frame([NapeOpcode.getLayerCount]))
        case .currentLayer:
            return .ready(frame([NapeOpcode.getCurrentLayer]))
        case .liveOrientation:
            return .ready(frame([NapeOpcode.miscGroup, NapeOpcode.getOrientation]))
        case .storedOrientation(let firmwareLayer):
            guard (1 ... NapeOpcode.userLayerCount).contains(firmwareLayer) else {
                return .rejected("Stored orientation is read only for firmware layers 1–8.")
            }
            return .ready(frame([
                NapeOpcode.miscGroup,
                NapeOpcode.getLayerOrientation,
                UInt8(firmwareLayer),
            ]))
        }
    }

    /// Packets the companion is allowed to put on the wire.
    /// Anything else, including every documented SET, is refused.
    static func isAllowlistedRead(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == NapeOpcode.packetLength else { return false }
        let command = bytes[0]
        if command == NapeOpcode.getFirmware
            || command == NapeOpcode.getLayerCount
            || command == NapeOpcode.getCurrentLayer
        {
            return bytes.dropFirst().allSatisfy { $0 == 0 }
        }
        guard command == NapeOpcode.miscGroup else { return false }
        let subcommand = bytes[1]
        if subcommand == NapeOpcode.getOrientation {
            return bytes.dropFirst(2).allSatisfy { $0 == 0 }
        }
        if subcommand == NapeOpcode.getLayerOrientation {
            let layer = bytes[2]
            guard (1 ... UInt8(NapeOpcode.userLayerCount)).contains(layer) else { return false }
            return bytes.dropFirst(3).allSatisfy { $0 == 0 }
        }
        return false
    }

    private static func frame(_ prefix: [UInt8]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: NapeOpcode.packetLength)
        for (index, byte) in prefix.enumerated() where index < bytes.count {
            bytes[index] = byte
        }
        return bytes
    }
}
