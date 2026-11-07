// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import XCTest
@testable import NapeProtocol

final class NamesTests: XCTestCase {
    func testNamesRoundTripAndFallBack() {
        let suite = "nape-protocol-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        XCTAssertNotNil(defaults)
        guard let defaults else { return }
        defaults.removePersistentDomain(forName: suite)

        XCTAssertEqual(LayerNames.load(from: defaults), LayerNames.defaults())

        var edited = LayerNames.defaults()
        edited[2] = "  Design\n"
        edited[3] = ""
        edited[4] = String(repeating: "A", count: 50)
        LayerNames.save(edited, to: defaults)

        let loaded = LayerNames.load(from: defaults)
        XCTAssertEqual(loaded.count, 8)
        XCTAssertEqual(loaded[2], "Design")
        XCTAssertEqual(loaded[3], "Layer 3")
        XCTAssertEqual(loaded[4].count, 40)
        XCTAssertEqual(LayerNames.statusTitle(displayLayer: 2, names: loaded), "L2 Design")
        XCTAssertEqual(LayerNames.statusTitle(displayLayer: 3, names: loaded), "L3")
        defaults.removePersistentDomain(forName: suite)
    }
}
