// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import XCTest
@testable import NapeProtocol

enum Fixture {
    /// Published measurement from dobachi, NapeProConfiguration
    /// `docs/keychron-launcher-investigation.md`
    /// (commit 1bca8c004c02e18bf41021da4116cb2955faed24).
    /// The 32-byte frame around it is constructed from the documented layout
    /// (command 0xA1, ASCII at byte 1, NUL terminated). It is not a captured trace.
    static let firmwareV123ZK = "v1.2.3-ZK Jun 3 2026 17:59:21"

    static let wired = SeenInterface(
        vendorID: 0x3434,
        productID: 0x0440,
        productName: "Nape Pro",
        primaryUsagePage: 0xFF60,
        primaryUsage: 0x61
    )

    static func receiver(productID: Int, usagePage: Int = 0xFF60, usage: Int = 0x61) -> SeenInterface {
        SeenInterface(
            vendorID: 0x3434,
            productID: productID,
            productName: nil,
            primaryUsagePage: usagePage,
            primaryUsage: usage
        )
    }

    static func frame(_ prefix: [UInt8]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 32)
        for (index, byte) in prefix.enumerated() where index < bytes.count {
            bytes[index] = byte
        }
        return bytes
    }

    static func firmwareFrame(_ text: String) -> [UInt8] {
        var bytes = frame([0xA1])
        for (index, byte) in text.utf8.enumerated() where index + 1 < bytes.count {
            bytes[index + 1] = byte
        }
        return bytes
    }
}

extension CompanionEngine {
    /// Feeds the connect probe until a current-layer reply has been accepted.
    @discardableResult
    mutating func bringUp(
        interfaces: [SeenInterface] = [Fixture.wired],
        firmwareLayer: UInt8 = 1,
        viaCount: UInt8 = 9,
        firmware: String? = Fixture.firmwareV123ZK,
        at now: Date
    ) -> MenuPresentation {
        interfacesChanged(interfaces)
        var packet = connectionOpened(at: now)
        var clock = now
        var guardrail = 0
        while let outbound = packet {
            guardrail += 1
            XCTAssertLessThan(guardrail, 8)
            XCTAssertTrue(NapeQuery.isAllowlistedRead(outbound))
            let reply: [UInt8]
            switch outbound[0] {
            case 0xA1:
                reply = Fixture.firmwareFrame(firmware ?? "")
            case 0x11:
                reply = Fixture.frame([0x11, viaCount])
            case 0xA3:
                reply = Fixture.frame([0xA3, firmwareLayer])
            default:
                XCTFail("Connect probe sent \(outbound[0]) before the layer reply")
                return presentation(at: clock)
            }
            clock = clock.addingTimeInterval(0.01)
            receive(bytes: reply, reportID: 0, at: clock)
            if outbound[0] == 0xA3 {
                return presentation(at: clock)
            }
            packet = tick(at: clock)
        }
        XCTFail("Connect probe ended before a layer reply")
        return presentation(at: clock)
    }
}
