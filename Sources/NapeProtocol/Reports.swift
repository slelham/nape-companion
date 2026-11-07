// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import Foundation

enum ReportBytes {
    static func payload(from bytes: [UInt8], reportID: UInt32) -> [UInt8]? {
        if bytes.count == NapeOpcode.packetLength {
            return bytes
        }
        guard bytes.count > NapeOpcode.packetLength else { return nil }
        if bytes[0] == UInt8(truncatingIfNeeded: reportID), isCommand(bytes[1]) {
            return Array(bytes.dropFirst().prefix(NapeOpcode.packetLength))
        }
        if isCommand(bytes[0]) {
            return Array(bytes.prefix(NapeOpcode.packetLength))
        }
        return nil
    }

    private static func isCommand(_ byte: UInt8) -> Bool {
        byte == NapeOpcode.getLayerCount
            || byte == NapeOpcode.getFirmware
            || byte == NapeOpcode.getCurrentLayer
            || byte == NapeOpcode.miscGroup
    }
}

struct OrientationValue: Equatable {
    var index: Int
    var degrees: Int
}

enum LayerDecode: Equatable {
    case user(firmwareLayer: Int, displayLayer: Int)
    case rejected(String)
}

enum OrientationDecode: Equatable {
    case value(OrientationValue)
    case rejected(String)
}

enum NapeDecode {
    static func matches(_ query: Query, payload: [UInt8]) -> Bool {
        guard payload.count == NapeOpcode.packetLength else { return false }
        switch query {
        case .firmware:
            return payload[0] == NapeOpcode.getFirmware
        case .layerCount:
            return payload[0] == NapeOpcode.getLayerCount
        case .currentLayer:
            return payload[0] == NapeOpcode.getCurrentLayer
        case .liveOrientation:
            return payload[0] == NapeOpcode.miscGroup && payload[1] == NapeOpcode.getOrientation
        case .storedOrientation:
            return payload[0] == NapeOpcode.miscGroup && payload[1] == NapeOpcode.getLayerOrientation
        }
    }

    /// Firmware indexes 1–8 are the user layers. Display labels are 0–7.
    /// Indexes outside that range are rejected. They are not clamped onto a layer.
    static func currentLayer(_ payload: [UInt8]) -> LayerDecode {
        guard payload.count == NapeOpcode.packetLength, payload[0] == NapeOpcode.getCurrentLayer else {
            return .rejected("Current-layer reply did not start with 0xA3.")
        }
        let index = Int(payload[1])
        guard (1 ... NapeOpcode.userLayerCount).contains(index) else {
            return .rejected(
                "Current-layer reply index \(index) is outside firmware layers 1–8 (shown as layers 0–7)."
            )
        }
        return .user(firmwareLayer: index, displayLayer: index - 1)
    }

    static func orientation(_ payload: [UInt8], subcommand: UInt8) -> OrientationDecode {
        guard payload.count == NapeOpcode.packetLength,
              payload[0] == NapeOpcode.miscGroup,
              payload[1] == subcommand
        else {
            return .rejected("Orientation reply did not match subcommand 0x\(hex(subcommand)).")
        }
        let index = Int(payload[2])
        guard (0 ..< NapeOpcode.orientationSteps).contains(index) else {
            return .rejected("Orientation step \(index) is outside 0–7.")
        }
        return .value(OrientationValue(
            index: index,
            degrees: index * NapeOpcode.orientationStepDegrees
        ))
    }

    /// ASCII from byte 1 until the first NUL. No prefix is added.
    /// dobachi records both `v1.2.3-ZK …` and a later `010205…` form.
    static func firmwareText(_ payload: [UInt8]) -> String? {
        guard payload.count == NapeOpcode.packetLength, payload[0] == NapeOpcode.getFirmware else {
            return nil
        }
        var collected: [UInt8] = []
        for byte in payload.dropFirst() {
            if byte == 0 { break }
            guard byte >= 0x20, byte < 0x7F else { return nil }
            collected.append(byte)
        }
        guard !collected.isEmpty, let text = String(bytes: collected, encoding: .utf8) else {
            return nil
        }
        return text
    }

    static func layerCount(_ payload: [UInt8]) -> Int? {
        guard payload.count == NapeOpcode.packetLength, payload[0] == NapeOpcode.getLayerCount else {
            return nil
        }
        let count = Int(payload[1])
        guard count > 0 else { return nil }
        return count
    }

    private static func hex(_ byte: UInt8) -> String {
        String(format: "%02X", byte)
    }
}
