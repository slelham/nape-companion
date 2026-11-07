// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import XCTest
@testable import NapeProtocol

final class EngineTests: XCTestCase {
    func testWiredProbeShowsDisplayLayerAndClearsItWhenUnplugged() {
        var engine = CompanionEngine()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let live = engine.bringUp(firmwareLayer: 1, at: start)
        XCTAssertTrue(live.isLive)
        XCTAssertEqual(live.title, "L0")
        XCTAssertTrue(info(live).contains("Layer 0 · Layer 0"))
        XCTAssertTrue(info(live).contains("Firmware \(Fixture.firmwareV123ZK)"))
        XCTAssertTrue(info(live).contains("VIA layer count 9"))
        XCTAssertTrue(info(live).contains("Documented path"))
        XCTAssertTrue(live.entries.contains(.rename))

        finishOrientation(engine: &engine, liveStep: 2, storedStep: 2, at: start.addingTimeInterval(0.05))
        let angled = engine.presentation(at: start.addingTimeInterval(0.1))
        XCTAssertTrue(info(angled).contains("OctaShift 90°"))
        XCTAssertFalse(info(angled).contains("stored"))

        engine.interfacesChanged([])
        let gone = engine.presentation(at: start.addingTimeInterval(0.2))
        XCTAssertFalse(gone.isLive)
        XCTAssertEqual(gone.title, "–")
        XCTAssertFalse(info(gone).contains("Layer 0"))
        XCTAssertFalse(info(gone).contains("OctaShift 90"))
        XCTAssertTrue(info(gone).contains("unplugged"))
    }

    func testDisplayIndexIsFirmwareIndexMinusOne() {
        var engine = CompanionEngine()
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let live = engine.bringUp(firmwareLayer: 4, at: now)
        XCTAssertEqual(live.title, "L3")
        XCTAssertTrue(info(live).contains("Layer 3 · Layer 3"))
    }

    func testStoredOrientationUsesTheFirmwareIndex() {
        var engine = CompanionEngine()
        let now = Date(timeIntervalSince1970: 1_700_000_200)
        _ = engine.bringUp(firmwareLayer: 1, at: now)
        let stored = nextOrientationPacket(engine: &engine, at: now.addingTimeInterval(0.2))
        XCTAssertEqual(Array(stored.prefix(3)), [0xA7, 0x38, 0x01])
    }

    func testDifferentLiveAndStoredAnglesStayVisible() {
        var engine = CompanionEngine()
        let now = Date(timeIntervalSince1970: 1_700_000_300)
        _ = engine.bringUp(firmwareLayer: 3, at: now)
        finishOrientation(engine: &engine, liveStep: 2, storedStep: 5, at: now.addingTimeInterval(0.2))
        let text = info(engine.presentation(at: now.addingTimeInterval(0.3)))
        XCTAssertTrue(text.contains("OctaShift 90° live, 225° stored on this layer"), text)
    }

    func testLayerChangeDoesNotKeepThePreviousAngle() {
        var engine = CompanionEngine()
        let now = Date(timeIntervalSince1970: 1_700_000_400)
        _ = engine.bringUp(firmwareLayer: 1, at: now)
        finishOrientation(engine: &engine, liveStep: 2, storedStep: 5, at: now.addingTimeInterval(0.2))

        let later = now.addingTimeInterval(PollTiming.interval + 0.3)
        guard let poll = engine.tick(at: later) else {
            return XCTFail("Expected a poll")
        }
        XCTAssertEqual(poll[0], 0xA3)
        engine.receive(bytes: Fixture.frame([0xA3, 8]), reportID: 0, at: later.addingTimeInterval(0.01))
        let switched = engine.presentation(at: later.addingTimeInterval(0.02))
        XCTAssertEqual(switched.title, "L7")
        XCTAssertTrue(switched.isLive)
        XCTAssertTrue(info(switched).contains("OctaShift angle was not read"), info(switched))
        XCTAssertFalse(info(switched).contains("225°"))
        XCTAssertFalse(info(switched).contains("90°"))
    }

    func testOutOfRangeLayerIsNotShownAsLive() {
        var engine = CompanionEngine()
        let now = Date(timeIntervalSince1970: 1_700_000_500)
        _ = engine.bringUp(firmwareLayer: 2, at: now)
        finishOrientation(engine: &engine, liveStep: 0, storedStep: 0, at: now.addingTimeInterval(0.05))
        let later = now.addingTimeInterval(1)
        guard let poll = engine.tick(at: later) else { return XCTFail("Expected a poll") }
        XCTAssertEqual(poll[0], 0xA3)
        engine.receive(bytes: Fixture.frame([0xA3, 0]), reportID: 0, at: later.addingTimeInterval(0.01))
        let failed = engine.presentation(at: later.addingTimeInterval(0.02))
        XCTAssertFalse(failed.isLive)
        XCTAssertEqual(failed.title, "!")
        XCTAssertTrue(info(failed).contains("index 0"))
        XCTAssertTrue(info(failed).contains("not live"))
        XCTAssertTrue(info(failed).contains("Layer 1"))
    }

    func testTimeoutDropsTheLiveClaim() {
        var engine = CompanionEngine()
        let now = Date(timeIntervalSince1970: 1_700_000_600)
        _ = engine.bringUp(firmwareLayer: 2, at: now)
        finishOrientation(engine: &engine, liveStep: 0, storedStep: 0, at: now.addingTimeInterval(0.05))
        let sent = now.addingTimeInterval(1)
        XCTAssertEqual(engine.tick(at: sent)?.first, 0xA3)
        let timedOut = sent.addingTimeInterval(PollTiming.responseTimeout + 0.01)
        XCTAssertNil(engine.tick(at: timedOut))
        let failed = engine.presentation(at: timedOut)
        XCTAssertFalse(failed.isLive)
        XCTAssertEqual(failed.title, "!")
        XCTAssertTrue(info(failed).contains("did not answer"))
        XCTAssertTrue(info(failed).contains("not live"))
    }

    func testStaleReadingIsNotPresentedAsLive() {
        var engine = CompanionEngine()
        let now = Date(timeIntervalSince1970: 1_700_000_700)
        _ = engine.bringUp(firmwareLayer: 6, at: now)
        let stale = now.addingTimeInterval(PollTiming.liveWindow + 1)
        let shown = engine.presentation(at: stale)
        XCTAssertFalse(shown.isLive)
        XCTAssertEqual(shown.title, "!")
        XCTAssertFalse(shown.entries.contains(.info("Live")))
        XCTAssertTrue(info(shown).contains("not live"))

        _ = engine.tick(at: stale)
        guard case .failed = engine.phase else {
            return XCTFail("Expected the engine to leave the live phase")
        }
    }

    func testSleepAndWakeDoNotKeepALayer() {
        var engine = CompanionEngine()
        let now = Date(timeIntervalSince1970: 1_700_000_800)
        _ = engine.bringUp(at: now)
        engine.sleep()
        engine.interfacesChanged([Fixture.wired])
        let sleeping = engine.presentation(at: now.addingTimeInterval(0.2))
        XCTAssertEqual(sleeping.title, "–")
        XCTAssertFalse(info(sleeping).contains("Layer 0"))
        XCTAssertTrue(info(sleeping).contains("asleep"))

        engine.noteWake()
        engine.interfacesChanged([Fixture.wired])
        let waking = engine.presentation(at: now.addingTimeInterval(0.3))
        XCTAssertEqual(waking.title, "…")
        XCTAssertFalse(waking.isLive)
    }

    func testCustomNameIsLocalAndDisappearsWhenTheDeviceDoes() {
        var engine = CompanionEngine(names: LayerNames.defaults())
        var names = LayerNames.defaults()
        names[0] = "Design"
        engine.replaceNames(names)
        let now = Date(timeIntervalSince1970: 1_700_000_900)
        let live = engine.bringUp(at: now)
        XCTAssertEqual(live.title, "L0 Design")
        XCTAssertTrue(live.accessibilityLabel.contains("Design"))

        engine.interfacesChanged([])
        let gone = engine.presentation(at: now.addingTimeInterval(0.2))
        XCTAssertFalse(info(gone).contains("Design"))
        XCTAssertTrue(gone.entries.contains(.rename))
    }

    func testReceiverPathIsLabeledUnverified() {
        var engine = CompanionEngine()
        let now = Date(timeIntervalSince1970: 1_700_001_000)
        let live = engine.bringUp(
            interfaces: [Fixture.receiver(productID: 0xD026)],
            firmwareLayer: 8,
            at: now
        )
        XCTAssertEqual(live.title, "L7")
        XCTAssertTrue(live.isLive)
        XCTAssertTrue(info(live).contains("Unverified"))
        XCTAssertTrue(info(live).contains("Keychron Link-KM"))
        XCTAssertTrue(live.accessibilityLabel.contains("unverified"))
    }

    func testMouseCollectionIsAnErrorNotAMissingDevice() {
        var engine = CompanionEngine()
        let now = Date(timeIntervalSince1970: 1_700_001_050)
        let mouse = SeenInterface(
            vendorID: 0x3434,
            productID: 0x0440,
            productName: "Nape Pro",
            primaryUsagePage: 0x01,
            primaryUsage: 0x02,
            transport: "USB"
        )
        engine.interfacesChanged([mouse])
        XCTAssertNil(engine.desiredDeviceIndex)
        let shown = engine.presentation(at: now)
        XCTAssertEqual(shown.title, "!")
        XCTAssertFalse(shown.isLive)
        let text = info(shown)
        XCTAssertTrue(text.contains("0x0001/0x0002"), text)
        XCTAssertTrue(text.contains("0xFF60"), text)
        XCTAssertTrue(text.contains("not opened"), text.lowercased())
        XCTAssertFalse(text.contains("Layer 0"))
    }

    func testRegistryFailureIsNotReportedAsUnplugged() {
        var engine = CompanionEngine()
        let now = Date(timeIntervalSince1970: 1_700_001_060)
        engine.interfacesChanged([], registryStatus: 0x2BC)
        let shown = engine.presentation(at: now)
        XCTAssertEqual(shown.title, "!")
        XCTAssertFalse(shown.isLive)
        XCTAssertTrue(info(shown).contains("HID services"))
        XCTAssertTrue(info(shown).contains("0x000002BC"))
    }

    func testOpenFailureIsNotALiveLayer() {
        var engine = CompanionEngine()
        let now = Date(timeIntervalSince1970: 1_700_001_100)
        engine.interfacesChanged([Fixture.wired])
        engine.openFailed(ioReturn: HIDResult.exclusiveAccess, at: now)
        let failed = engine.presentation(at: now)
        XCTAssertEqual(failed.title, "!")
        XCTAssertFalse(failed.isLive)
        XCTAssertTrue(info(failed).contains("already open"))
        XCTAssertFalse(engine.readyToOpen(at: now))
        XCTAssertTrue(engine.readyToOpen(at: now.addingTimeInterval(PollTiming.interval)))
    }

    func testIgnoredReportDoesNotCompleteTheQuery() {
        var engine = CompanionEngine()
        let now = Date(timeIntervalSince1970: 1_700_001_200)
        engine.interfacesChanged([Fixture.wired])
        let firmware = engine.connectionOpened(at: now)
        XCTAssertEqual(firmware?.first, 0xA1)
        engine.receive(bytes: Fixture.frame([0xA3, 1]), reportID: 0, at: now.addingTimeInterval(0.01))
        let stillConnecting = engine.presentation(at: now.addingTimeInterval(0.02))
        XCTAssertEqual(stillConnecting.title, "…")
        XCTAssertFalse(stillConnecting.isLive)
    }

    private func finishOrientation(
        engine: inout CompanionEngine,
        liveStep: UInt8,
        storedStep: UInt8,
        at now: Date
    ) {
        guard let live = engine.tick(at: now) else {
            return XCTFail("Expected the live orientation query")
        }
        XCTAssertEqual(Array(live.prefix(2)), [0xA7, 0x20])
        engine.receive(bytes: Fixture.frame([0xA7, 0x20, liveStep]), reportID: 0, at: now.addingTimeInterval(0.01))
        guard let stored = engine.tick(at: now.addingTimeInterval(0.02)) else {
            return XCTFail("Expected the stored orientation query")
        }
        XCTAssertEqual(stored[0], 0xA7)
        XCTAssertEqual(stored[1], 0x38)
        engine.receive(
            bytes: Fixture.frame([0xA7, 0x38, storedStep]),
            reportID: 0,
            at: now.addingTimeInterval(0.03)
        )
    }

    private func nextOrientationPacket(engine: inout CompanionEngine, at now: Date) -> [UInt8] {
        guard let live = engine.tick(at: now) else {
            XCTFail("Expected a query")
            return []
        }
        engine.receive(bytes: Fixture.frame([0xA7, 0x20, 0]), reportID: 0, at: now.addingTimeInterval(0.01))
        guard let stored = engine.tick(at: now.addingTimeInterval(0.02)) else {
            XCTFail("Expected the stored query")
            return []
        }
        XCTAssertEqual(live[1], 0x20)
        return stored
    }

    private func info(_ presentation: MenuPresentation) -> String {
        presentation.entries.compactMap { entry in
            guard case .info(let text) = entry else { return nil }
            return text
        }.joined(separator: "\n")
    }
}
