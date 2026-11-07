// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import Foundation

enum LayerNames {
    static let count = 8
    static let defaultsKey = "layerDisplayNames"
    static let maxLength = 40

    static func defaultName(displayLayer: Int) -> String {
        "Layer \(displayLayer)"
    }

    static func defaults() -> [String] {
        (0 ..< count).map(defaultName(displayLayer:))
    }

    static func normalize(_ raw: [String]) -> [String] {
        var names = defaults()
        let limit = min(count, raw.count)
        for index in 0 ..< limit {
            names[index] = sanitize(raw[index], displayLayer: index)
        }
        return names
    }

    static func sanitize(_ raw: String, displayLayer: Int) -> String {
        let scalars = raw.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }
        let trimmed = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return defaultName(displayLayer: displayLayer)
        }
        if trimmed.count > maxLength {
            return String(trimmed.prefix(maxLength))
        }
        return trimmed
    }

    static func load(from defaults: UserDefaults) -> [String] {
        guard let stored = defaults.stringArray(forKey: defaultsKey) else {
            return Self.defaults()
        }
        return normalize(stored)
    }

    static func save(_ names: [String], to defaults: UserDefaults) {
        defaults.set(normalize(names), forKey: defaultsKey)
    }

    static func statusTitle(displayLayer: Int, names: [String]) -> String {
        let safe = normalize(names)
        guard (0 ..< count).contains(displayLayer) else { return "!" }
        let name = safe[displayLayer]
        if name == defaultName(displayLayer: displayLayer) {
            return "L\(displayLayer)"
        }
        let visible = name.count > 18 ? String(name.prefix(18)) : name
        return "L\(displayLayer) \(visible)"
    }

    static func menuName(displayLayer: Int, names: [String]) -> String {
        let safe = normalize(names)
        guard (0 ..< count).contains(displayLayer) else { return "Layer" }
        return safe[displayLayer]
    }
}
