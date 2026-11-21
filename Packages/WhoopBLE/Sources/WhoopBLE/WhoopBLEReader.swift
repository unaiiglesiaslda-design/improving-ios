import Foundation
import CoreBluetooth
import Combine
import WhoopProtocol

/// One decoded reading emitted by `WhoopBLEReader` — pure data, no persistence or UI.
public enum WhoopReading {
    /// Standard BLE Heart Rate Measurement (`0x2A37`).
    /// On WHOOP 5/MG, `rrMs` already accounts for the firmware millisecond quirk (`rrRawTicks`).
    case standardHeartRate(bpm: Int, rrMs: [Int], contact: StandardHRContact, timestamp: Date)
    /// Standard BLE Battery Level (`0x2A19`) or custom battery reply.
    case battery(percent: Int, millivolts: Int?, charging: Bool?, timestamp: Date)
    /// Decoded live WHOOP custom-service frame (`parseFrame` + `extractStreams`).
    case liveFrame(frame: ParsedFrame, streams: Streams)
    /// One historical offload chunk collected between `HISTORY_START` and `HISTORY_END`.
    /// Call `ackHistoricalChunk(endData:)` after consuming/saving this chunk so the strap
    /// advances its trim pointer safely.
    case historicalChunk(unix: UInt32, trimCursor: UInt32, endData: [UInt8], streams: Streams)
    /// Strap signalled `HISTORY_COMPLETE`.
    case historicalComplete
    /// Raw Device Information Service value (`0x2A24` model, `0x2A25` serial, `0x2A27` hwRev).
    case deviceInfo(model: String?, serial: String?, hardwareRevision: String?)
    /// Diagnostic / lifecycle log message.
    case log(String)
}

/// Pure CoreBluetooth reader for WHOOP 4.0 (`6108…`) and WHOOP 5.0 / MG (`fd4b…`) straps.
///
/// Handles scanning, connecting, family-aware handshake (WHOOP 4.0 confirmed-write bond vs.
/// WHOOP 5.0/MG static `CLIENT_HELLO`), notification subscriptions, fragment reassembly,
/// CRC-gated decoding via `WhoopProtocol`, standard `0x2A37`/`0x2A19` parsing, and
/// resumable historical offload with explicit safe-trim acknowledgement.
///
/// No UI, no database, and no analytics — consume `readings` or `@Published` properties.
@MainActor
public final class WhoopBLEReader: NSObject, ObservableObject {

    public enum ConnectionState: String, Equatable {
        case idle
        case scanning
        case connecting
        case discovering
        case ready
        case disconnected
    }

    // Standard SIG UUIDs
    public static let heartRateServiceUUID      = CBUUID(string: "180D")
    public static let heartRateMeasurementUUID  = CBUUID(string: "2A37")
    public static let batteryServiceUUID        = CBUUID(string: "180F")
    public static let batteryLevelUUID          = CBUUID(string: "2A19")
    public static let deviceInfoServiceUUID     = CBUUID(string: "180A")
    public static let disModelNumberUUID        = CBUUID(string: "2A24")
    public static let disSerialNumberUUID       = CBUUID(string: "2A25")
    public static let disHardwareRevisionUUID   = CBUUID(string: "2A27")

    // Published live state
    @Published public private(set) var connectionState: ConnectionState = .idle
    @Published public private(set) var bluetoothState: CBManagerState = .unknown
    @Published public private(set) var connectedModel: WhoopModel?
    @Published public private(set) var strapName: String?
    @Published public private(set) var latestHeartRate: Int?
    @Published public private(set) var latestBatteryPercent: Int?
    @Published public private(set) var isOffloadingHistory: Bool = false

    /// Stream of all decoded readings from the strap.
    public let readings: AsyncStream<WhoopReading>
    private let continuation: AsyncStream<WhoopReading>.Continuation

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var targetModel: WhoopModel = .whoop4
    private var activeFamily: DeviceFamily = .whoop4
    private var reassembler = Reassembler(family: .whoop4)
    private var commandSeq: UInt8 = 1
    private var connectHandshakeDone = false
    private var pendingHistoryFrames: [ParsedFrame] = []
    private var disModel: String?
    private var disSerial: String?
    private var disHardwareRev: String?

    public override init() {
        var cont: AsyncStream<WhoopReading>.Continuation!
        self.readings = AsyncStream<WhoopReading> { cont = $0 }
        self.continuation = cont
        super.init()
        self.central = CBCentralManager(delegate: self, queue: .main)
    }

    deinit {
        continuation.finish()
    }

    // MARK: - Public Controls

    /// Start scanning for a WHOOP strap (scans both 4.0 and 5.0/MG custom services if `model` is nil).
    public func startScanning(for model: WhoopModel? = nil) {
        if let model { targetModel = model }
        guard central.state == .poweredOn else {
            emit(.log("Bluetooth not powered on (state=\(central.state.rawValue))"))
            return
        }
        let services: [CBUUID] = model.map { [$0.scanService] } ?? [
            WhoopModel.whoop4.scanService,
            WhoopModel.whoop5mg.scanService,
        ]
        connectionState = .scanning
        central.scanForPeripherals(withServices: services, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,
        ])
        emit(.log("Scanning for WHOOP services: \(services.map(\.uuidString).joined(separator: ", "))"))
    }

    public func stopScanning() {
        central.stopScan()
        if connectionState == .scanning { connectionState = .idle }
    }

    public func disconnect() {
        central.stopScan()
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        resetLinkState()
        connectionState = .disconnected
    }

    /// Send a safe, curated `WhoopCommand` framed for the connected strap family (4.0 CRC8 vs 5/MG puffin CRC16).
    public func sendCommand(_ command: WhoopCommand, payload: [UInt8] = [0x00], withResponse: Bool = true) {
        guard let peripheral, let cmdChar = commandCharacteristic else {
            emit(.log("Cannot send \(command.label): not connected"))
            return
        }
        let seq = nextSeq()
        let bytes: [UInt8]
        switch activeFamily {
        case .whoop4:
            bytes = command.frame(seq: seq, payload: payload)
        case .whoop5:
            bytes = puffinCommandFrame(cmd: command.rawValue, seq: seq, payload: payload)
        }
        let writeType: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
        peripheral.writeValue(Data(bytes), for: cmdChar, type: writeType)
    }

    /// Toggle realtime custom-service HR streaming on the strap.
    public func setRealtimeHR(enabled: Bool) {
        sendCommand(.toggleRealtimeHR, payload: [enabled ? 0x01 : 0x00])
    }

    /// Ask the strap for its stored historical record range (`GET_DATA_RANGE`).
    public func requestDataRange() {
        sendCommand(.getDataRange, payload: [0x00])
    }

    /// Start draining banked historical biometric data from the strap (`SEND_HISTORICAL_DATA`).
    public func requestHistoricalData() {
        pendingHistoryFrames.removeAll(keepingCapacity: true)
        isOffloadingHistory = true
        sendCommand(.sendHistoricalData, payload: [0x00])
    }

    /// Acknowledge a historical chunk (`HISTORICAL_DATA_RESULT`) ONLY AFTER you have durably saved it.
    /// This advances the strap's trim cursor so the strap may free those banked records.
    public func ackHistoricalChunk(endData: [UInt8]) {
        guard endData.count >= 8 else { return }
        let payload: [UInt8] = [0x01] + Array(endData.prefix(8))
        sendCommand(.historicalDataResult, payload: payload, withResponse: true)
    }

    /// Ask the strap to abort an in-progress historical offload without trimming unacked chunks.
    public func abortHistoricalData() {
        isOffloadingHistory = false
        pendingHistoryFrames.removeAll()
        sendCommand(.abortHistoricalTransmits, payload: [0x00])
    }

    // MARK: - Internals

    private func nextSeq() -> UInt8 {
        let s = commandSeq
        commandSeq = commandSeq &+ 1
        if commandSeq == 0 { commandSeq = 1 }
        return s
    }

    private func emit(_ reading: WhoopReading) {
        continuation.yield(reading)
    }

    private func resetLinkState() {
        peripheral = nil
        commandCharacteristic = nil
        connectHandshakeDone = false
        isOffloadingHistory = false
        pendingHistoryFrames.removeAll()
        disModel = nil
        disSerial = nil
        disHardwareRev = nil
    }

    private func runPostBondHandshake() {
        guard !connectHandshakeDone else { return }
        connectHandshakeDone = true
        connectionState = .ready

        switch activeFamily {
        case .whoop4:
            sendCommand(.getHelloHarvard, payload: [0x00])
            sendCommand(.reportVersionInfo, payload: [0x00])
            sendCommand(.getClock, payload: [0x00])
            sendCommand(.sendR10R11Realtime, payload: [0x00]) // stop ~2/s raw flood
            sendCommand(.getDataRange, payload: [0x00])
        case .whoop5:
            sendCommand(.getHello, payload: [0x01])
            sendCommand(.getBatteryLevel, payload: [0x00])
            sendCommand(.getDataRange, payload: [0x00])
        }
    }

    private func handleCompleteFrame(_ raw: [UInt8]) {
        let parsed = parseFrame(raw, family: activeFamily)
        guard parsed.ok else { return }

        let nowUnix = Int(Date().timeIntervalSince1970)

        // Check historical metadata state machine (HISTORY_START / HISTORY_END / HISTORY_COMPLETE)
        if parsed.typeName == "METADATA" {
            switch classifyHistoricalMeta(parsed) {
            case .start:
                isOffloadingHistory = true
                pendingHistoryFrames.removeAll(keepingCapacity: true)
                return
            case .end(let unix, let trim):
                let chunk = pendingHistoryFrames
                pendingHistoryFrames.removeAll(keepingCapacity: true)
                let streams = extractHistoricalStreams(
                    chunk,
                    deviceClockRef: nowUnix,
                    wallClockRef: nowUnix,
                    family: activeFamily
                )
                // Extract the 8-byte ack block (WHOOP 4: frame[17..<25], WHOOP 5: frame[21..<29])
                let ackStart = (activeFamily == .whoop5) ? 21 : 17
                let endData = raw.count >= ackStart + 8 ? Array(raw[ackStart..<(ackStart + 8)]) : []
                emit(.historicalChunk(unix: unix, trimCursor: trim, endData: endData, streams: streams))
                return
            case .complete:
                isOffloadingHistory = false
                pendingHistoryFrames.removeAll()
                emit(.historicalComplete)
                return
            case .other:
                break
            }
        }

        if isOffloadingHistory && parsed.typeName == "HISTORICAL_DATA" {
            pendingHistoryFrames.append(parsed)
            return
        }

        let streams = extractStreams([parsed], deviceClockRef: nowUnix, wallClockRef: nowUnix, family: activeFamily)
        if let lastHR = streams.hr.last {
            latestHeartRate = lastHR.bpm
        }
        if let batt = streams.battery.last, let soc = batt.soc {
            latestBatteryPercent = Int(soc.rounded())
            emit(.battery(percent: Int(soc.rounded()), millivolts: batt.mv, charging: batt.charging, timestamp: Date()))
        }
        emit(.liveFrame(frame: parsed, streams: streams))
    }
}

// MARK: - CBCentralManagerDelegate

extension WhoopBLEReader: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor in
            self.bluetoothState = state
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let uuidStrings = serviceUUIDs.map { $0.uuidString.lowercased() }
        Task { @MainActor in
            let detectedModel: WhoopModel
            if uuidStrings.contains(DeviceFamily.whoop5.serviceUUIDString) {
                detectedModel = .whoop5mg
            } else if uuidStrings.contains(DeviceFamily.whoop4.serviceUUIDString) {
                detectedModel = .whoop4
            } else {
                detectedModel = self.targetModel
            }

            self.connectedModel = detectedModel
            self.activeFamily = detectedModel.deviceFamily
            self.reassembler = Reassembler(family: self.activeFamily)
            self.strapName = peripheral.name
            self.peripheral = peripheral
            self.peripheral?.delegate = self
            self.connectionState = .connecting
            central.stopScan()
            central.connect(peripheral, options: nil)
            self.emit(.log("Connecting to \(peripheral.name ?? "WHOOP") as \(detectedModel.displayName)"))
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.connectionState = .discovering
            self.connectHandshakeDone = false
            peripheral.discoverServices([
                self.activeFamily == .whoop5 ? WhoopModel.whoop5mg.scanService : WhoopModel.whoop4.scanService,
                Self.heartRateServiceUUID,
                Self.batteryServiceUUID,
                Self.deviceInfoServiceUUID,
            ])
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let msg = error?.localizedDescription
        Task { @MainActor in
            self.resetLinkState()
            self.connectionState = .disconnected
            self.emit(.log("Disconnected\(msg.map { ": \($0)" } ?? "")"))
        }
    }
}

// MARK: - CBPeripheralDelegate

extension WhoopBLEReader: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil, let chars = service.characteristics else { return }
        Task { @MainActor in
            let cmdUUID = CBUUID(string: self.activeFamily.commandCharacteristicUUIDString)
            for c in chars {
                if c.uuid == cmdUUID {
                    self.commandCharacteristic = c
                } else if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: c)
                }

                if c.uuid == Self.batteryLevelUUID
                    || c.uuid == Self.disModelNumberUUID
                    || c.uuid == Self.disSerialNumberUUID
                    || c.uuid == Self.disHardwareRevisionUUID {
                    peripheral.readValue(for: c)
                }
            }

            if let cmdChar = self.commandCharacteristic, !self.connectHandshakeDone {
                switch self.activeFamily {
                case .whoop4:
                    // Trigger OS bond via one confirmed GET_BATTERY_LEVEL write on 61080002.
                    let bondProbe = WhoopCommand.getBatteryLevel.frame(seq: self.nextSeq(), payload: [0x00])
                    peripheral.writeValue(Data(bondProbe), for: cmdChar, type: .withResponse)
                case .whoop5:
                    // Write fixed CLIENT_HELLO to fd4b0002 to start session.
                    peripheral.writeValue(Data(DeviceFamily.whoop5ClientHello), for: cmdChar, type: .withResponse)
                }
            }
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let errText = error?.localizedDescription
        Task { @MainActor in
            if let errText {
                self.emit(.log("Write error on \(characteristic.uuid.uuidString): \(errText)"))
                return
            }
            if characteristic.uuid == CBUUID(string: self.activeFamily.commandCharacteristicUUIDString) {
                self.runPostBondHandshake()
            }
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        let uuid = characteristic.uuid

        Task { @MainActor in
            if uuid == Self.heartRateMeasurementUUID {
                if let parsed = StandardHeartRate.parse(bytes) {
                    // WHOOP 5 firmware emits raw ms on 0x2A37 instead of 1/1024s ticks.
                    let rrMs = (self.activeFamily == .whoop5) ? parsed.rrRawTicks : parsed.rr
                    self.latestHeartRate = parsed.hr
                    self.emit(.standardHeartRate(bpm: parsed.hr, rrMs: rrMs, contact: parsed.contact, timestamp: Date()))
                }
                return
            }

            if uuid == Self.batteryLevelUUID, let pct = bytes.first {
                self.latestBatteryPercent = Int(pct)
                self.emit(.battery(percent: Int(pct), millivolts: nil, charging: nil, timestamp: Date()))
                return
            }

            if uuid == Self.disModelNumberUUID || uuid == Self.disSerialNumberUUID || uuid == Self.disHardwareRevisionUUID {
                let text = String(bytes: bytes, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
                if uuid == Self.disModelNumberUUID { self.disModel = text }
                if uuid == Self.disSerialNumberUUID { self.disSerial = text }
                if uuid == Self.disHardwareRevisionUUID { self.disHardwareRev = text }
                self.emit(.deviceInfo(model: self.disModel, serial: self.disSerial, hardwareRevision: self.disHardwareRev))
                return
            }

            // Custom WHOOP service fragmented notification -> Reassembler -> parseFrame
            let completeFrames = self.reassembler.feed(bytes)
            for frame in completeFrames {
                self.handleCompleteFrame(frame)
            }
        }
    }
}
