// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import Foundation

enum PollTiming {
    static let interval: TimeInterval = 0.45
    static let responseTimeout: TimeInterval = 0.8
    static let liveWindow: TimeInterval = 2.5
}

struct ActiveReading: Equatable {
    var firmwareLayer: Int
    var displayLayer: Int
    var liveOrientation: OrientationValue?
    var storedOrientation: OrientationValue?
    var firmwareText: String?
    var viaLayerCount: Int?
    var orientationNote: String?
    var transport: TransportKind
    var confirmedAt: Date
}

struct FailureState: Equatable {
    var transport: TransportKind?
    var message: String
    var lastConfirmed: ActiveReading?
}

enum DisconnectDetail: Equatable {
    case nothingAttached
    case asleep
    case removed
}

enum Phase: Equatable {
    case disconnected(DisconnectDetail)
    case connecting(TransportKind)
    case live(ActiveReading)
    case failed(FailureState)
}

struct CompanionEngine {
    private(set) var phase: Phase = .disconnected(.nothingAttached)
    private(set) var names: [String]
    private(set) var desiredDeviceIndex: Int?
    private var transport: TransportKind?
    private var queue: [Query] = []
    private var inFlight: Query?
    private var sentAt: Date?
    private var pollDue = Date.distantPast
    private var firmwareText: String?
    private var viaLayerCount: Int?
    private var firmwareLayer: Int?
    private var liveOrientation: OrientationValue?
    private var storedOrientation: OrientationValue?
    private var orientationNote: String?
    private var asleep = false

    init(names: [String] = LayerNames.defaults()) {
        self.names = LayerNames.normalize(names)
    }

    mutating func replaceNames(_ names: [String]) {
        self.names = LayerNames.normalize(names)
    }

    mutating func interfacesChanged(_ interfaces: [SeenInterface], registryStatus: Int32 = 0) {
        if asleep {
            clearSelection()
            phase = .disconnected(.asleep)
            return
        }
        if registryStatus != 0, interfaces.isEmpty {
            showBlocked(
                "IOKit could not list HID services (0x\(String(format: "%08X", UInt32(bitPattern: registryStatus)))). No interface was opened."
            )
            return
        }
        switch NapeIdentity.classify(interfaces) {
        case .absent:
            let asleep: Bool
            if case .disconnected(.asleep) = phase {
                asleep = true
            } else {
                asleep = false
            }
            let hadDevice = desiredDeviceIndex != nil
            clearSelection()
            if asleep {
                phase = .disconnected(.asleep)
            } else if hadDevice {
                phase = .disconnected(.removed)
            } else {
                phase = .disconnected(.nothingAttached)
            }
        case .open(let index, let chosen):
            if desiredDeviceIndex == index, transport == chosen, desiredDeviceIndex != nil {
                return
            }
            select(index: index, transport: chosen)
        case .blocked(let message):
            showBlocked(message)
        }
    }

    mutating func sleep() {
        asleep = true
        clearSelection()
        phase = .disconnected(.asleep)
    }

    /// Clears the asleep marker so the next device list can connect again.
    mutating func noteWake() {
        asleep = false
        clearSelection()
        phase = .disconnected(.nothingAttached)
    }

    func readyToOpen(at now: Date) -> Bool {
        desiredDeviceIndex != nil && inFlight == nil && now >= pollDue
    }

    mutating func connectionOpened(at now: Date) -> [UInt8]? {
        guard transport != nil else { return nil }
        queue = [.firmware, .layerCount, .currentLayer, .liveOrientation]
        inFlight = nil
        sentAt = nil
        if let transport {
            phase = .connecting(transport)
        }
        return takeNext(at: now)
    }

    mutating func openFailed(ioReturn: Int32, at now: Date) {
        let previous = lastReading
        queue = []
        inFlight = nil
        sentAt = nil
        pollDue = now.addingTimeInterval(PollTiming.interval)
        phase = .failed(FailureState(
            transport: transport,
            message: HIDFailureMessage.message(for: ioReturn),
            lastConfirmed: previous
        ))
    }

    mutating func sendFailed(ioReturn: Int32, at now: Date) {
        inFlight = nil
        sentAt = nil
        queue = []
        pollDue = now.addingTimeInterval(PollTiming.interval)
        phase = .failed(FailureState(
            transport: transport,
            message: HIDFailureMessage.message(for: ioReturn),
            lastConfirmed: lastReading
        ))
    }

    mutating func receive(bytes: [UInt8], reportID: UInt32, at now: Date) {
        guard let query = inFlight else { return }
        guard let payload = ReportBytes.payload(from: bytes, reportID: reportID) else { return }
        guard NapeDecode.matches(query, payload: payload) else { return }
        inFlight = nil
        sentAt = nil
        apply(query, payload: payload, at: now)
        if queue.isEmpty {
            pollDue = now.addingTimeInterval(PollTiming.interval)
        }
    }

    mutating func tick(at now: Date) -> [UInt8]? {
        timeoutInFlight(at: now)
        demoteStaleLive(at: now)
        guard desiredDeviceIndex != nil else { return nil }
        if inFlight != nil { return nil }
        if queue.isEmpty {
            guard now >= pollDue else { return nil }
            enqueuePoll()
        }
        return takeNext(at: now)
    }

    func presentation(at now: Date) -> MenuPresentation {
        MenuPresentation.make(phase: presentedPhase(at: now), names: names, now: now)
    }

    private func presentedPhase(at now: Date) -> Phase {
        guard case .live(let reading) = phase else { return phase }
        if now.timeIntervalSince(reading.confirmedAt) <= PollTiming.liveWindow {
            return phase
        }
        return .failed(FailureState(
            transport: reading.transport,
            message: "The layer reading is older than \(seconds(PollTiming.liveWindow)) seconds, so it is not shown as live.",
            lastConfirmed: reading
        ))
    }

    private var lastReading: ActiveReading? {
        switch phase {
        case .live(let reading):
            return reading
        case .failed(let failure):
            return failure.lastConfirmed
        case .disconnected, .connecting:
            return nil
        }
    }

    private mutating func showBlocked(_ message: String) {
        if case .failed(let failure) = phase, failure.message == message, desiredDeviceIndex == nil {
            return
        }
        clearSelection()
        phase = .failed(FailureState(transport: nil, message: message, lastConfirmed: nil))
    }

    private mutating func select(index: Int, transport: TransportKind) {
        clearCaches()
        desiredDeviceIndex = index
        self.transport = transport
        queue = []
        inFlight = nil
        sentAt = nil
        pollDue = .distantPast
        phase = .connecting(transport)
    }

    private mutating func clearSelection() {
        clearCaches()
        desiredDeviceIndex = nil
        transport = nil
        queue = []
        inFlight = nil
        sentAt = nil
    }

    private mutating func clearCaches() {
        firmwareText = nil
        viaLayerCount = nil
        firmwareLayer = nil
        liveOrientation = nil
        storedOrientation = nil
        orientationNote = nil
    }

    private mutating func enqueuePoll() {
        queue = [.currentLayer, .liveOrientation]
        if let firmwareLayer, (1 ... NapeOpcode.userLayerCount).contains(firmwareLayer) {
            queue.append(.storedOrientation(firmwareLayer: firmwareLayer))
        }
    }

    private mutating func takeNext(at now: Date) -> [UInt8]? {
        while !queue.isEmpty {
            let query = queue.removeFirst()
            guard case .ready(let bytes) = NapeQuery.packet(for: query),
                  NapeQuery.isAllowlistedRead(bytes)
            else { continue }
            inFlight = query
            sentAt = now
            return bytes
        }
        pollDue = now.addingTimeInterval(PollTiming.interval)
        return nil
    }

    private mutating func timeoutInFlight(at now: Date) {
        guard let query = inFlight, let sentAt else { return }
        guard now.timeIntervalSince(sentAt) > PollTiming.responseTimeout else { return }
        inFlight = nil
        self.sentAt = nil
        switch query {
        case .currentLayer:
            fail(
                "The trackball did not answer the current-layer query within \(seconds(PollTiming.responseTimeout)) seconds. The config interface had been opened; this is not a missing device.",
                at: now
            )
        case .liveOrientation:
            liveOrientation = nil
            orientationNote = "Orientation query timed out."
            updateLiveFieldsIfShowing()
            scheduleIfIdle(at: now)
        case .storedOrientation:
            storedOrientation = nil
            orientationNote = "Orientation query timed out."
            updateLiveFieldsIfShowing()
            scheduleIfIdle(at: now)
        case .firmware, .layerCount:
            scheduleIfIdle(at: now)
        }
    }

    private mutating func scheduleIfIdle(at now: Date) {
        if queue.isEmpty {
            pollDue = now.addingTimeInterval(PollTiming.interval)
        }
    }

    private mutating func demoteStaleLive(at now: Date) {
        guard inFlight == nil, case .live(let reading) = phase else { return }
        guard now.timeIntervalSince(reading.confirmedAt) > PollTiming.liveWindow else { return }
        phase = .failed(FailureState(
            transport: reading.transport,
            message: "The layer reading is older than \(seconds(PollTiming.liveWindow)) seconds, so it is not shown as live.",
            lastConfirmed: reading
        ))
        pollDue = now
    }

    private mutating func apply(_ query: Query, payload: [UInt8], at now: Date) {
        switch query {
        case .firmware:
            firmwareText = NapeDecode.firmwareText(payload)
            updateLiveFieldsIfShowing()
        case .layerCount:
            viaLayerCount = NapeDecode.layerCount(payload)
            updateLiveFieldsIfShowing()
        case .currentLayer:
            applyCurrentLayer(payload, at: now)
        case .liveOrientation:
            applyLiveOrientation(payload)
        case .storedOrientation(let firmwareLayer):
            applyStoredOrientation(payload, firmwareLayer: firmwareLayer)
        }
    }

    private mutating func applyCurrentLayer(_ payload: [UInt8], at now: Date) {
        switch NapeDecode.currentLayer(payload) {
        case .rejected(let message):
            fail(message, at: now)
        case .user(let firmware, let display):
            if firmwareLayer != firmware {
                liveOrientation = nil
                storedOrientation = nil
                orientationNote = nil
            }
            firmwareLayer = firmware
            guard let transport else {
                fail("A layer reply arrived with no selected device.", at: now)
                return
            }
            if !queue.contains(where: { query in
                if case .storedOrientation(let layer) = query { return layer == firmware }
                return false
            }) {
                queue.append(.storedOrientation(firmwareLayer: firmware))
            }
            phase = .live(makeReading(displayLayer: display, firmwareLayer: firmware, transport: transport, at: now))
        }
    }

    private mutating func applyLiveOrientation(_ payload: [UInt8]) {
        switch NapeDecode.orientation(payload, subcommand: NapeOpcode.getOrientation) {
        case .value(let value):
            liveOrientation = value
            if orientationNote == "Orientation query timed out." {
                orientationNote = nil
            }
        case .rejected(let message):
            liveOrientation = nil
            orientationNote = message
        }
        updateLiveFieldsIfShowing()
    }

    private mutating func applyStoredOrientation(_ payload: [UInt8], firmwareLayer expected: Int) {
        guard expected == firmwareLayer else { return }
        switch NapeDecode.orientation(payload, subcommand: NapeOpcode.getLayerOrientation) {
        case .value(let value):
            storedOrientation = value
        case .rejected(let message):
            storedOrientation = nil
            orientationNote = message
        }
        updateLiveFieldsIfShowing()
    }

    private mutating func updateLiveFieldsIfShowing() {
        guard case .live(let reading) = phase, let transport else { return }
        phase = .live(makeReading(
            displayLayer: reading.displayLayer,
            firmwareLayer: reading.firmwareLayer,
            transport: transport,
            at: reading.confirmedAt
        ))
    }

    private func makeReading(
        displayLayer: Int,
        firmwareLayer: Int,
        transport: TransportKind,
        at now: Date
    ) -> ActiveReading {
        ActiveReading(
            firmwareLayer: firmwareLayer,
            displayLayer: displayLayer,
            liveOrientation: liveOrientation,
            storedOrientation: storedOrientation,
            firmwareText: firmwareText,
            viaLayerCount: viaLayerCount,
            orientationNote: orientationNote,
            transport: transport,
            confirmedAt: now
        )
    }

    private mutating func fail(_ message: String, at now: Date) {
        let previous = lastReading
        queue = []
        pollDue = now.addingTimeInterval(PollTiming.interval)
        phase = .failed(FailureState(
            transport: transport,
            message: message,
            lastConfirmed: previous
        ))
    }

    private func seconds(_ value: TimeInterval) -> String {
        if value < 1 {
            return String(format: "%.1f", value)
        }
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
