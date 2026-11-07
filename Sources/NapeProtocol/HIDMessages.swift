// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import Foundation

/// Public IOReturn values from Apple's IOReturn.h (sys_iokit | code).
/// The app passes the code from IOHIDDeviceOpen / IOHIDDeviceSetReport.
enum HIDResult {
    static let success = Int32(bitPattern: 0)
    static let exclusiveAccess = Int32(bitPattern: 0xE000_02C5)
    static let notPrivileged = Int32(bitPattern: 0xE000_02C1)
    static let notPermitted = Int32(bitPattern: 0xE000_02E2)
    static let unsupported = Int32(bitPattern: 0xE000_02C7)
}

enum HIDFailureMessage {
    static func message(for code: Int32) -> String {
        switch code {
        case HIDResult.exclusiveAccess:
            return "The config interface is already open in another app. Keychron Launcher can keep working while this app is refused. Quit Launcher, or the browser tab that has the trackball open, and this menu will try again. The mouse collection was not opened."
        case HIDResult.notPrivileged, HIDResult.notPermitted:
            return "macOS refused the HID open (\(hex(code))). If Nape Companion appears under System Settings → Privacy & Security → Input Monitoring, turn it on and relaunch. The app opens the vendor collection, usage page 0xFF60 usage 0x61, and does not open the mouse pointer collection."
        case HIDResult.unsupported:
            return "This interface rejected the HID report (\(hex(code))). The app only speaks the 32-byte RAW HID protocol."
        default:
            return "The HID request failed (\(hex(code)))."
        }
    }

    private static func hex(_ code: Int32) -> String {
        String(format: "0x%08X", UInt32(bitPattern: code))
    }
}
