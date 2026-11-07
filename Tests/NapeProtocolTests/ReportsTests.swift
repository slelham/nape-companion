// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import XCTest
@testable import NapeProtocol

final class ReportsTests: XCTestCase {
    func testAllowlistIsOnlyTheFiveReads() {
        let queries: [Query] = [
            .firmware,
            .layerCount,
            .currentLayer,
            .liveOrientation,
        ] + (1 ... 8).map { Query.storedOrientation(firmwareLayer: $0) }

        for query in queries {
            guard case .ready(let bytes) = NapeQuery.packet(for: query) else {
                return XCTFail("Expected a packet for \(query)")
            }
            XCTAssertEqual(bytes.count, 32)
            XCTAssertTrue(NapeQuery.isAllowlistedRead(bytes), "\(query)")
        }

        guard case .rejected = NapeQuery.packet(for: .storedOrientation(firmwareLayer: 0)) else {
            return XCTFail("Firmware layer 0 must not be sent")
        }
        guard case .rejected = NapeQuery.packet(for: .storedOrientation(firmwareLayer: 9)) else {
            return XCTFail("Firmware layer 9 must not be sent")
        }
    }

    func testReadPacketsMatchTheDocumentedPrefixes() {
        XCTAssertEqual(prefix(.firmware), [0xA1])
        XCTAssertEqual(prefix(.layerCount), [0x11])
        XCTAssertEqual(prefix(.currentLayer), [0xA3])
        XCTAssertEqual(prefix(.liveOrientation), [0xA7, 0x20])
        XCTAssertEqual(prefix(.storedOrientation(firmwareLayer: 1)), [0xA7, 0x38, 0x01])
        XCTAssertEqual(prefix(.storedOrientation(firmwareLayer: 8)), [0xA7, 0x38, 0x08])
    }

    func testWritesAreNotAllowlisted() {
        let writes: [[UInt8]] = [
            [0x05, 0x01, 0x00, 0x00],
            [0x15, 0x01, 0x00, 0x01],
            [0xA7, 0x2D, 0x03],
            [0xA7, 0x34, 0x02],
            [0xA7, 0x39, 0x03, 0x05],
            [0xA7, 0x22, 0x01],
            [0xA7, 0x38, 0x00],
            [0xA7, 0x38, 0x09],
        ]
        for write in writes {
            XCTAssertFalse(NapeQuery.isAllowlistedRead(Fixture.frame(write)), "\(write)")
        }
    }

    func testCurrentLayerMappingDoesNotClamp() {
        expectLayer([0xA3, 1], firmware: 1, display: 0)
        expectLayer([0xA3, 3], firmware: 3, display: 2)
        expectLayer([0xA3, 8], firmware: 8, display: 7)
        expectRejectedLayer([0xA3, 0], containing: "index 0")
        expectRejectedLayer([0xA3, 9], containing: "index 9")
    }

    func testOrientationByteIsTheStepTimes45() {
        // dobachi: reply byte 2 is the step, and step × 45 is degrees.
        expectAngle([0xA7, 0x20, 0], subcommand: 0x20, degrees: 0)
        expectAngle([0xA7, 0x20, 2], subcommand: 0x20, degrees: 90)
        expectAngle([0xA7, 0x20, 7], subcommand: 0x20, degrees: 315)
        expectAngle([0xA7, 0x38, 5], subcommand: 0x38, degrees: 225)
        guard case .rejected(let message) = NapeDecode.orientation(Fixture.frame([0xA7, 0x20, 8]), subcommand: 0x20) else {
            return XCTFail("Step 8 must be rejected")
        }
        XCTAssertTrue(message.contains("8"))
    }

    func testDocumentedFirmwareStringAndTheLaterNumericForm() {
        let text = NapeDecode.firmwareText(Fixture.firmwareFrame(Fixture.firmwareV123ZK))
        XCTAssertEqual(text, Fixture.firmwareV123ZK)

        // dobachi notes v1.2.5 changed to a form like "010205…". This frame is synthetic.
        let numeric = NapeDecode.firmwareText(Fixture.firmwareFrame("010205"))
        XCTAssertEqual(numeric, "010205")
        XCTAssertFalse(numeric?.hasPrefix("v") ?? true)
    }

    func testLayerCountUsesTheViaReplyByte() {
        // The value 9 is the measured Nape Pro result. The frame is synthetic.
        XCTAssertEqual(NapeDecode.layerCount(Fixture.frame([0x11, 9])), 9)
        XCTAssertEqual(NapeDecode.layerCount(Fixture.frame([0x11, 8])), 8)
        XCTAssertNil(NapeDecode.layerCount(Fixture.frame([0x11, 0])))
    }

    func testReportFraming() {
        let body = Fixture.frame([0xA3, 4])
        XCTAssertEqual(ReportBytes.payload(from: body, reportID: 0), body)

        var withID = [UInt8](repeating: 0, count: 33)
        withID[0] = 0
        withID.replaceSubrange(1 ..< 33, with: body)
        XCTAssertEqual(ReportBytes.payload(from: withID, reportID: 0), body)

        var longReply = body
        longReply.append(contentsOf: [UInt8](repeating: 0xFF, count: 8))
        XCTAssertEqual(ReportBytes.payload(from: longReply, reportID: 0), body)

        XCTAssertNil(ReportBytes.payload(from: Array(body.dropLast()), reportID: 0))
        XCTAssertNil(ReportBytes.payload(from: [UInt8](repeating: 0, count: 33), reportID: 0))
    }

    private func prefix(_ query: Query) -> [UInt8] {
        guard case .ready(let bytes) = NapeQuery.packet(for: query) else {
            XCTFail("Missing packet")
            return []
        }
        return Array(bytes.prefix { $0 != 0 })
    }

    private func expectLayer(_ prefix: [UInt8], firmware: Int, display: Int) {
        guard case .user(let gotFirmware, let gotDisplay) = NapeDecode.currentLayer(Fixture.frame(prefix)) else {
            return XCTFail("Expected a user layer for \(prefix)")
        }
        XCTAssertEqual(gotFirmware, firmware)
        XCTAssertEqual(gotDisplay, display)
    }

    private func expectRejectedLayer(_ prefix: [UInt8], containing: String) {
        guard case .rejected(let message) = NapeDecode.currentLayer(Fixture.frame(prefix)) else {
            return XCTFail("Expected a rejection for \(prefix)")
        }
        XCTAssertTrue(message.contains(containing), message)
    }

    private func expectAngle(_ prefix: [UInt8], subcommand: UInt8, degrees: Int) {
        guard case .value(let value) = NapeDecode.orientation(Fixture.frame(prefix), subcommand: subcommand) else {
            return XCTFail("Expected an angle for \(prefix)")
        }
        XCTAssertEqual(value.degrees, degrees)
    }
}
