// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import Foundation
import IOKit
import IOKit.hid

struct RegistryHit {
    var service: io_service_t
    var location: Int
    var interface: SeenInterface
}

struct RegistryCensusResult {
    var status: Int32
    var hits: [RegistryHit]
}

/// Lists HID services without opening them. The caller owns each returned
/// service and must IOObjectRelease it. Serial numbers are not read.
enum RegistryCensus {
    static func collect() -> RegistryCensusResult {
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(kIOHIDDeviceKey),
            &iterator
        )
        guard status == KERN_SUCCESS else {
            return RegistryCensusResult(status: Int32(status), hits: [])
        }
        defer { IOObjectRelease(iterator) }

        var hits: [RegistryHit] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            let interface = readInterface(service)
            let location = integerProperty(service, key: kIOHIDLocationIDKey) ?? 0
            if NapeIdentity.isWatched(interface) {
                hits.append(RegistryHit(service: service, location: location, interface: interface))
            } else {
                IOObjectRelease(service)
            }
        }
        return RegistryCensusResult(status: Int32(status), hits: hits)
    }

    private static func readInterface(_ service: io_registry_entry_t) -> SeenInterface {
        let primaryPage = integerProperty(service, key: kIOHIDPrimaryUsagePageKey)
        let primaryUsage = integerProperty(service, key: kIOHIDPrimaryUsageKey)
        return SeenInterface(
            vendorID: integerProperty(service, key: kIOHIDVendorIDKey) ?? 0,
            productID: integerProperty(service, key: kIOHIDProductIDKey) ?? 0,
            productName: stringProperty(service, key: kIOHIDProductKey),
            primaryUsagePage: primaryPage,
            primaryUsage: primaryUsage,
            usagePairs: usagePairs(service),
            transport: stringProperty(service, key: kIOHIDTransportKey)
        )
    }

    private static func usagePairs(_ service: io_registry_entry_t) -> [UsagePair] {
        guard let raw = copyProperty(service, key: kIOHIDDeviceUsagePairsKey),
              CFGetTypeID(raw) == CFArrayGetTypeID()
        else { return [] }
        let array = unsafeBitCast(raw, to: CFArray.self) as NSArray
        var pairs: [UsagePair] = []
        for item in array {
            guard let dictionary = item as? NSDictionary else { continue }
            let page = number(dictionary[kIOHIDDeviceUsagePageKey])
            let usage = number(dictionary[kIOHIDDeviceUsageKey])
            if let page, let usage {
                pairs.append(UsagePair(page: page, usage: usage))
            }
        }
        return pairs
    }

    private static func integerProperty(_ service: io_registry_entry_t, key: String) -> Int? {
        guard let raw = copyProperty(service, key: key) else { return nil }
        return integer(raw)
    }

    private static func stringProperty(_ service: io_registry_entry_t, key: String) -> String? {
        guard let raw = copyProperty(service, key: key),
              CFGetTypeID(raw) == CFStringGetTypeID()
        else { return nil }
        return unsafeBitCast(raw, to: CFString.self) as String
    }

    private static func copyProperty(_ service: io_registry_entry_t, key: String) -> CFTypeRef? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func integer(_ value: CFTypeRef) -> Int? {
        guard CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
        var number: Int64 = 0
        let cfNumber = unsafeBitCast(value, to: CFNumber.self)
        guard CFNumberGetValue(cfNumber, .sInt64Type, &number) else { return nil }
        return Int(number)
    }

    private static func number(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let number = value as? Int { return number }
        return nil
    }
}
