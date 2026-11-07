// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import Foundation
import IOKit
import IOKit.hid

protocol HIDMonitorDelegate: AnyObject {
    func hidMonitorInterfacesChanged()
    func hidMonitorReceived(bytes: [UInt8], reportID: UInt32)
}

/// Watches the RAW HID collection only (usage page 0xFF60, usage 0x61).
/// The mouse-pointer collection is not in the match list and is never opened.
/// Opens use kIOHIDOptionsTypeNone. This monitor does not seize the device.
final class HIDMonitor {
    weak var delegate: HIDMonitorDelegate?

    private struct Slot {
        var device: IOHIDDevice
        var location: Int
        var interface: SeenInterface
    }

    private let bufferLength = 64
    private var manager: IOHIDManager?
    private var devices: [Slot] = []
    private var openedDevice: IOHIDDevice?
    private var openedLocation: Int?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var generation: UInt64 = 0
    private var callbackGeneration: UInt64 = 0
    private var suspended = false
    private var started = false

    var interfaces: [SeenInterface] {
        devices.map(\.interface)
    }

    var openedIndex: Int? {
        guard let openedLocation else { return nil }
        return devices.firstIndex { $0.location == openedLocation }
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !started else { return }
        started = true
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        let matches: [[String: Any]] = NapeIdentity.matches().map { match in
            [
                kIOHIDVendorIDKey: match.vendorID,
                kIOHIDProductIDKey: match.productID,
                kIOHIDPrimaryUsagePageKey: match.usagePage,
                kIOHIDPrimaryUsageKey: match.usage,
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let matched: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().refreshDeviceList()
        }
        let removed: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().refreshDeviceList()
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, matched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, removed, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        // Shared open of the matched RAW collections so arrival and removal
        // callbacks run. This is not kIOHIDOptionsTypeSeizeDevice.
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        refreshDeviceList()
    }

    func refreshDeviceList() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !suspended, let manager else { return }
        let previous = interfaces
        let previousOpen = openedLocation
        devices = copyDevices(manager).sorted { lhs, rhs in
            if lhs.location != rhs.location { return lhs.location < rhs.location }
            return lhs.interface.productID < rhs.interface.productID
        }
        if let previousOpen, !devices.contains(where: { $0.location == previousOpen }) {
            closeSession()
        }
        if interfaces != previous || openedLocation != previousOpen {
            delegate?.hidMonitorInterfacesChanged()
        }
    }

    /// Registers the input callback on one already-matched RAW interface.
    /// Returns an IOReturn. Zero means the session is ready for output reports.
    func open(index: Int) -> Int32 {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !suspended else { return kIOReturnNotOpen }
        guard devices.indices.contains(index) else { return kIOReturnNoDevice }
        let slot = devices[index]
        if openedLocation == slot.location, openedDevice != nil {
            return HIDResult.success
        }
        closeSession()
        let result = IOHIDDeviceOpen(slot.device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { return result }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferLength)
        buffer.initialize(repeating: 0, count: bufferLength)
        reportBuffer = buffer
        callbackGeneration = generation
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDReportCallback = { context, result, _, _, reportID, report, length in
            guard let context, result == kIOReturnSuccess, length > 0 else { return }
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
            monitor.deliver(bytes: bytes, reportID: reportID)
        }
        IOHIDDeviceRegisterInputReportCallback(slot.device, buffer, bufferLength, callback, context)
        IOHIDDeviceScheduleWithRunLoop(
            slot.device,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
        openedDevice = slot.device
        openedLocation = slot.location
        return HIDResult.success
    }

    func setReport(_ bytes: [UInt8]) -> Int32 {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let device = openedDevice else { return kIOReturnNotOpen }
        guard NapeQuery.isAllowlistedRead(bytes) else { return kIOReturnUnsupported }
        var copy = bytes
        return copy.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return kIOReturnNoMemory }
            return IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(Int(NapeOpcode.reportID)),
                base,
                CFIndex(buffer.count)
            )
        }
    }

    func close() {
        dispatchPrecondition(condition: .onQueue(.main))
        closeSession()
    }

    func suspend() {
        dispatchPrecondition(condition: .onQueue(.main))
        suspended = true
        closeSession()
        devices = []
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    func resume() {
        dispatchPrecondition(condition: .onQueue(.main))
        suspended = false
        guard let manager else { return }
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        refreshDeviceList()
    }

    private func deliver(bytes: [UInt8], reportID: UInt32) {
        guard generation == callbackGeneration, !suspended else { return }
        let forward = { self.delegate?.hidMonitorReceived(bytes: bytes, reportID: reportID) }
        if Thread.isMainThread {
            forward()
        } else {
            DispatchQueue.main.async(execute: forward)
        }
    }

    private func closeSession() {
        generation &+= 1
        if let device = openedDevice {
            IOHIDDeviceUnscheduleFromRunLoop(
                device,
                CFRunLoopGetMain(),
                CFRunLoopMode.defaultMode.rawValue
            )
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        openedDevice = nil
        openedLocation = nil
        if let reportBuffer {
            reportBuffer.deinitialize(count: bufferLength)
            reportBuffer.deallocate()
            self.reportBuffer = nil
        }
    }

    private func copyDevices(_ manager: IOHIDManager) -> [Slot] {
        guard let copied = IOHIDManagerCopyDevices(manager) else { return [] }
        guard let set = copied as? NSSet else { return [] }
        var slots: [Slot] = []
        for item in set {
            guard let device = item as? IOHIDDevice else { continue }
            guard let slot = slot(for: device) else { continue }
            if slots.contains(where: { $0.location == slot.location && slot.location != 0 }) {
                continue
            }
            slots.append(slot)
        }
        return slots
    }

    private func slot(for device: IOHIDDevice) -> Slot? {
        guard let vendor = integer(device, key: kIOHIDVendorIDKey),
              let product = integer(device, key: kIOHIDProductIDKey)
        else { return nil }
        var usagePage = integer(device, key: kIOHIDPrimaryUsagePageKey)
            ?? integer(device, key: kIOHIDDeviceUsagePageKey)
        var usage = integer(device, key: kIOHIDPrimaryUsageKey)
            ?? integer(device, key: kIOHIDDeviceUsageKey)
        // The manager already filtered on the RAW collection. If the property
        // read is empty, keep the usage the match dictionary required.
        if usagePage == nil { usagePage = NapeOpcode.rawUsagePage }
        if usage == nil { usage = NapeOpcode.rawUsage }
        let interface = SeenInterface(
            vendorID: vendor,
            productID: product,
            productName: string(device, key: kIOHIDProductKey),
            primaryUsagePage: usagePage,
            primaryUsage: usage
        )
        let location = integer(device, key: kIOHIDLocationIDKey) ?? 0
        return Slot(device: device, location: location, interface: interface)
    }

    private func integer(_ device: IOHIDDevice, key: String) -> Int? {
        let raw = IOHIDDeviceGetProperty(device, key as CFString)
        if let number = raw as? NSNumber { return number.intValue }
        if let number = raw as? Int { return number }
        return nil
    }

    private func string(_ device: IOHIDDevice, key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }
}
