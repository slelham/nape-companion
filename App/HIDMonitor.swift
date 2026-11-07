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
        var service: io_service_t
        var location: Int
        var interface: SeenInterface
    }

    private let bufferLength = 64
    private var manager: IOHIDManager?
    private var managerScheduled = false
    private var slots: [Slot] = []
    private(set) var registryStatus: Int32 = 0
    private var openedDevice: IOHIDDevice?
    private var openedLocation: Int?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var generation: UInt64 = 0
    private var callbackGeneration: UInt64 = 0
    private var suspended = false
    private var started = false

    var interfaces: [SeenInterface] {
        slots.map(\.interface)
    }

    /// Product ids, transports, and usage pages. No serial number and no location id.
    var diagnosticSummary: String {
        let code = String(format: "%08X", UInt32(bitPattern: registryStatus))
        return "registry 0x\(code) \(NapeIdentity.diagnosticSummary(interfaces))"
    }

        var openedIndex: Int? {
        guard let openedLocation else { return nil }
        return slots.firstIndex { $0.location == openedLocation }
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !started else { return }
        started = true
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        // Vendor and product only, so a mouse-primary interface still wakes a
        // refresh. IOHIDManagerOpen is not called: that would open every match,
        // including the pointer collection. Nothing is seized.
        let products = [NapeOpcode.wiredProductID] + NapeIdentity.receivers.filter(\.attempted).map(\.productID)
        let matches: [[String: Any]] = products.map { product in
            [
                kIOHIDVendorIDKey: NapeOpcode.vendorID,
                kIOHIDProductIDKey: product,
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
        scheduleManager()
        refreshDeviceList()
    }

    func refreshDeviceList() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !suspended else { return }
        let census = RegistryCensus.collect()
        let previous = interfaces
        let previousStatus = registryStatus
        let previousOpen = openedLocation
        registryStatus = census.status
        let sorted = census.hits.sorted { lhs, rhs in
            if lhs.interface.productID != rhs.interface.productID {
                return lhs.interface.productID < rhs.interface.productID
            }
            if lhs.location != rhs.location { return lhs.location < rhs.location }
            return (lhs.interface.primaryUsagePage ?? 0) < (rhs.interface.primaryUsagePage ?? 0)
        }
        for slot in slots {
            IOObjectRelease(slot.service)
        }
        slots = sorted.map { hit in
            Slot(service: hit.service, location: hit.location, interface: hit.interface)
        }
        if let previousOpen, !slots.contains(where: { $0.location == previousOpen }) {
            closeSession()
        }
        if interfaces != previous || registryStatus != previousStatus || openedLocation != previousOpen {
            delegate?.hidMonitorInterfacesChanged()
        }
    }

    /// Registers the input callback on one already-matched RAW interface.
    /// Returns an IOReturn. Zero means the session is ready for output reports.
    func open(index: Int) -> Int32 {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !suspended else { return kIOReturnNotOpen }
        guard slots.indices.contains(index) else { return kIOReturnNoDevice }
        let slot = slots[index]
        guard NapeIdentity.isOpenableRaw(slot.interface) else { return kIOReturnUnsupported }
        if openedLocation == slot.location, openedDevice != nil {
            return HIDResult.success
        }
        closeSession()
        let device: IOHIDDevice? = IOHIDDeviceCreate(kCFAllocatorDefault, slot.service)
        guard let device else { return kIOReturnNoDevice }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
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
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferLength, callback, context)
        IOHIDDeviceScheduleWithRunLoop(
            device,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
        openedDevice = device
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
        releaseSlots()
        registryStatus = 0
        unscheduleManager()
    }

    func resume() {
        dispatchPrecondition(condition: .onQueue(.main))
        suspended = false
        scheduleManager()
        refreshDeviceList()
    }

    private func scheduleManager() {
        guard let manager, !managerScheduled else { return }
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        managerScheduled = true
    }

    private func unscheduleManager() {
        guard let manager, managerScheduled else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        managerScheduled = false
    }

    private func releaseSlots() {
        for slot in slots {
            IOObjectRelease(slot.service)
        }
        slots = []
    }

    private func deliver(bytes: [UInt8], reportID: UInt32) {
        guard generation == callbackGeneration, !suspended else { return }
        let forward = {
            self.delegate?.hidMonitorReceived(bytes: bytes, reportID: reportID)
            return
        }
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

}
