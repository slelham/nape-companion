// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import XCTest
@testable import NapeProtocol

final class IdentityTests: XCTestCase {
    func testMatchListIsTheWiredDeviceAndTwoUnverifiedReceivers() {
        let matches = NapeIdentity.matches()
        XCTAssertEqual(matches.count, 3)
        XCTAssertTrue(matches.allSatisfy {
            $0.vendorID == 0x3434 && $0.usagePage == 0xFF60 && $0.usage == 0x61
        })
        XCTAssertEqual(matches.map(\.productID), [0x0440, 0xD026, 0xD029])
        let attempted = NapeIdentity.receivers.filter(\.attempted).map(\.productID)
        XCTAssertEqual(attempted, [0xD026, 0xD029])
        XCTAssertTrue(NapeIdentity.receivers.contains { $0.productID == 0xD05A && !$0.attempted })
    }

    func testWiredRawInterfaceWinsOverAReceiver() {
        let choice = NapeIdentity.choose([
            Fixture.receiver(productID: 0xD026),
            Fixture.wired,
        ])
        guard case .open(let index, .wiredUSB) = choice else {
            return XCTFail("Expected the wired interface, got \(choice)")
        }
        XCTAssertEqual(index, 1)
    }

    func testReceiverIsChosenOnlyWithTheRawCollection() {
        let choice = NapeIdentity.choose([
            Fixture.receiver(productID: 0xD029, usagePage: 0xFFC1, usage: 0x01),
            Fixture.receiver(productID: 0xD029),
        ])
        guard case .open(let index, .receiverUnverified(let productID, let name)) = choice else {
            return XCTFail("Expected the RAW receiver interface, got \(choice)")
        }
        XCTAssertEqual(index, 1)
        XCTAssertEqual(productID, 0xD029)
        XCTAssertEqual(name, "Keychron Link-KM Type C")
    }

    func testOtherKeychronInterfacesAreIgnored() {
        let mousePointer = SeenInterface(
            vendorID: 0x3434,
            productID: 0x0440,
            productName: "Nape Pro",
            primaryUsagePage: 0x01,
            primaryUsage: 0x02
        )
        let keyboard = SeenInterface(
            vendorID: 0x3434,
            productID: 0x0ABC,
            productName: "Keychron keyboard",
            primaryUsagePage: 0xFF60,
            primaryUsage: 0x61
        )
        let mSeries = SeenInterface(
            vendorID: 0x3434,
            productID: 0xD060,
            productName: "M6",
            primaryUsagePage: 0xFFC1,
            primaryUsage: 0x01
        )
        let turboLink = Fixture.receiver(productID: 0xD05A)
        XCTAssertEqual(NapeIdentity.choose([mousePointer, keyboard, mSeries, turboLink]), .idle)
        XCTAssertEqual(NapeIdentity.choose([]), .idle)
        guard case .blocked(let message) = NapeIdentity.classify([mousePointer]) else {
            return XCTFail("A mouse-only Nape Pro must be reported, not treated as absent")
        }
        XCTAssertTrue(message.contains("0x0001/0x0002"), message)
        XCTAssertTrue(message.contains("0xFF60"), message)
        XCTAssertFalse(message.contains("serial"))
        XCTAssertNil(engineOpen(of: [mousePointer]))
    }

    func testBluetoothAndSecondaryRawAreNotOpened() {
        var bluetooth = Fixture.wired
        bluetooth.transport = "BluetoothLowEnergy"
        guard case .blocked(let bluetoothMessage) = NapeIdentity.classify([bluetooth]) else {
            return XCTFail("Bluetooth must not be opened")
        }
        XCTAssertTrue(bluetoothMessage.contains("Bluetooth"), bluetoothMessage)
        XCTAssertEqual(NapeIdentity.choose([bluetooth]), .idle)

        let mouse = SeenInterface(
            vendorID: 0x3434,
            productID: 0x0440,
            productName: "Nape Pro",
            primaryUsagePage: 0x01,
            primaryUsage: 0x02,
            usagePairs: [UsagePair(page: 0xFF60, usage: 0x61)],
            transport: "USB"
        )
        guard case .blocked(let pairMessage) = NapeIdentity.classify([mouse]) else {
            return XCTFail("A secondary RAW pair must not be opened")
        }
        XCTAssertTrue(pairMessage.contains("not the primary collection"), pairMessage)
        XCTAssertFalse(NapeIdentity.isOpenableRaw(mouse))

        let renamed = SeenInterface(
            vendorID: 0x3434,
            productID: 0x0999,
            productName: "Keychron Nape Pro",
            primaryUsagePage: 0x01,
            primaryUsage: 0x02,
            transport: "USB"
        )
        guard case .blocked(let nameMessage) = NapeIdentity.classify([renamed]) else {
            return XCTFail("A differently numbered Nape must be visible in the menu")
        }
        XCTAssertTrue(nameMessage.contains("0x0999"), nameMessage)
        XCTAssertFalse(NapeIdentity.isOpenableRaw(renamed))
    }

    private func engineOpen(of interfaces: [SeenInterface]) -> Int? {
        if case .open(let index, _) = NapeIdentity.classify(interfaces) { return index }
        return nil
    }
}
