import CoreBluetooth
import Foundation
import OSLog

enum GooseLogLevel: String {
  case debug
  case info
  case warn
  case error
}

struct GooseDiscoveredDevice: Identifiable, Equatable {
  let id: UUID
  let name: String
  let rssi: Int
}

struct GooseMessage: Identifiable {
  let id = UUID()
  let timestamp: Date
  let level: GooseLogLevel
  let source: String
  let title: String
  let body: String
}

struct GooseNotificationEvent {
  let deviceID: UUID
  let serviceUUID: String
  let characteristicUUID: String
  let value: Data
  let capturedAt: Date

  var rustDeviceType: String {
    characteristicUUID.lowercased().hasPrefix("610800") ? "GEN4" : "GOOSE"
  }
}

enum GooseSyncToastPhase: String {
  case syncing
  case synced
  case failed
}

struct GooseSyncToast: Identifiable, Equatable {
  let id = UUID()
  let phase: GooseSyncToastPhase
  let title: String
  let detail: String
}

struct GooseSyncFailure: Identifiable, Equatable {
  let id = UUID()
  let title: String
  let message: String
  let occurredAt: Date
}

final class GooseBLEClient: NSObject, ObservableObject {
  @Published private(set) var bluetoothState = "not requested"
  @Published private(set) var connectionState = "disconnected"
  @Published private(set) var isScanning = false
  @Published private(set) var discoveredDevices: [GooseDiscoveredDevice] = []
  @Published private(set) var messages: [GooseMessage] = []
  @Published private(set) var liveHeartRateBPM: Int?
  @Published private(set) var liveHeartRateSource = "waiting"
  @Published private(set) var liveHeartRateUpdatedAt: Date?
  @Published private(set) var reconnectState = "idle"
  @Published private(set) var rememberedDeviceDescription = "none"
  @Published private(set) var activeDeviceName = "WHOOP strap"
  @Published private(set) var activeDeviceIdentifier: UUID?
  @Published private(set) var selectedDeviceID: UUID?
  @Published private(set) var connectedAt: Date?
  @Published private(set) var lastSyncAt: Date?
  @Published private(set) var batteryLevelPercent: Int?
  @Published private(set) var batteryUpdatedAt: Date?
  @Published private(set) var firmwareVersion: String?
  @Published private(set) var modelNumber: String?
  @Published private(set) var hardwareRevision: String?
  @Published private(set) var softwareRevision: String?
  @Published private(set) var manufacturerName: String?
  @Published private(set) var isHistoricalSyncing = false
  @Published private(set) var historicalSyncStatus = "idle"
  @Published private(set) var historicalPacketCount = 0
  @Published private(set) var lastHistoricalSyncCompletedAt: Date?
  @Published private(set) var syncToast: GooseSyncToast?
  @Published private(set) var lastSyncFailure: GooseSyncFailure?
  @Published var syncFailureSheet: GooseSyncFailure?

  var onNotification: ((GooseNotificationEvent) -> Void)?

  private let logger = Logger(subsystem: "com.goose.swift", category: "ble")
  private let defaults = UserDefaults.standard
  private var central: CBCentralManager?
  private var peripherals: [UUID: CBPeripheral] = [:]
  private var activePeripheral: CBPeripheral?
  private var commandCharacteristic: CBCharacteristic?
  private var batteryLevelCharacteristic: CBCharacteristic?
  private var rememberedDeviceID: UUID?
  private var rememberedDeviceName: String?
  private var autoReconnectTargetID: UUID?
  private var autoReconnectInFlight = false
  private var startupReconnectAttempted = false
  private var pendingConnectionReason: String?
  private var pendingAutomaticHistoricalSyncReason: String?
  private var readySyncWorkItem: DispatchWorkItem?
  private var syncClearWorkItem: DispatchWorkItem?
  private var historicalCommandTimeoutWorkItem: DispatchWorkItem?
  private var historicalIdleWorkItem: DispatchWorkItem?
  private var pendingHistoricalCommand: PendingHistoricalCommand?
  private var nextHistoricalCommandSequence: UInt8 = 2
  private var historicalPacketsReceivedThisSync = 0
  private var historyEndAckQueued = false
  private var historyEndReceived = false
  private var historyCompleteReceived = false
  private var historicalSyncRunID = UUID()

  private enum DefaultsKey {
    static let rememberedDeviceID = "goose.swift.rememberedDeviceID"
    static let rememberedDeviceName = "goose.swift.rememberedDeviceName"
  }

  private static let restorationIdentifier = "com.goose.swift.central"

  private let whoopServices = [
    CBUUID(string: "fd4b0001-cce1-4033-93ce-002d5875f58a"),
    CBUUID(string: "61080001-8d6d-82b8-614a-1c8cb0f8dcc6"),
  ]

  private let commandCharacteristicIDs = [
    CBUUID(string: "fd4b0002-cce1-4033-93ce-002d5875f58a"),
    CBUUID(string: "61080002-8d6d-82b8-614a-1c8cb0f8dcc6"),
  ]

  private let notificationCharacteristicIDs = [
    CBUUID(string: "fd4b0003-cce1-4033-93ce-002d5875f58a"),
    CBUUID(string: "fd4b0004-cce1-4033-93ce-002d5875f58a"),
    CBUUID(string: "fd4b0005-cce1-4033-93ce-002d5875f58a"),
    CBUUID(string: "fd4b0007-cce1-4033-93ce-002d5875f58a"),
    CBUUID(string: "61080003-8d6d-82b8-614a-1c8cb0f8dcc6"),
    CBUUID(string: "61080004-8d6d-82b8-614a-1c8cb0f8dcc6"),
    CBUUID(string: "61080005-8d6d-82b8-614a-1c8cb0f8dcc6"),
    CBUUID(string: "61080007-8d6d-82b8-614a-1c8cb0f8dcc6"),
  ]

  private let standardHeartRateServiceID = CBUUID(string: "180D")
  private let standardHeartRateMeasurementID = CBUUID(string: "2A37")
  private let batteryServiceID = CBUUID(string: "180F")
  private let batteryLevelCharacteristicID = CBUUID(string: "2A19")
  private let deviceInformationServiceID = CBUUID(string: "180A")
  private let modelNumberCharacteristicID = CBUUID(string: "2A24")
  private let firmwareRevisionCharacteristicID = CBUUID(string: "2A26")
  private let hardwareRevisionCharacteristicID = CBUUID(string: "2A27")
  private let softwareRevisionCharacteristicID = CBUUID(string: "2A28")
  private let manufacturerNameCharacteristicID = CBUUID(string: "2A29")

  private enum HistoricalCommandKind {
    case getDataRange
    case sendHistoricalData
    case historicalDataResult

    var commandNumber: UInt8 {
      switch self {
      case .getDataRange: 34
      case .sendHistoricalData: 22
      case .historicalDataResult: 23
      }
    }

    var payload: [UInt8] {
      switch self {
      case .getDataRange, .sendHistoricalData:
        []
      case .historicalDataResult:
        [0, 0, 0, 0]
      }
    }

    var name: String {
      switch self {
      case .getDataRange: "GET_DATA_RANGE"
      case .sendHistoricalData: "SEND_HISTORICAL_DATA"
      case .historicalDataResult: "HISTORICAL_DATA_RESULT"
      }
    }
  }

  private struct PendingHistoricalCommand {
    let kind: HistoricalCommandKind
    let sequence: UInt8
  }

  private enum HistoricalMetadataKind: UInt16 {
    case historyStart = 1
    case historyEnd = 2
    case historyComplete = 3

    var name: String {
      switch self {
      case .historyStart: "HistoryStart"
      case .historyEnd: "HistoryEnd"
      case .historyComplete: "HistoryComplete"
      }
    }
  }

  private enum V5PacketType {
    static let command: UInt8 = 35
    static let commandResponse: UInt8 = 36
    static let puffinCommandResponse: UInt8 = 38
    static let historicalData: UInt8 = 47
    static let metadata: UInt8 = 49
    static let historicalIMUDataStream: UInt8 = 52
    static let puffinMetadata: UInt8 = 56
  }

  var canScan: Bool {
    central?.state == .poweredOn
  }

  var canConnect: Bool {
    canScan && !discoveredDevices.isEmpty && activePeripheral == nil
  }

  var canSendHello: Bool {
    activePeripheral != nil && commandCharacteristic != nil && connectionState == "ready"
  }

  var canSyncHistorical: Bool {
    canSendHello && !isHistoricalSyncing && supportsV5HistoricalSync
  }

  var canReconnectRemembered: Bool {
    central?.state == .poweredOn && activePeripheral == nil && rememberedDeviceID != nil
  }

  var hasRememberedDevice: Bool {
    rememberedDeviceID != nil
  }

  init(startCentral: Bool = true) {
    super.init()
    loadRememberedDevice()
    record(source: "app", title: "ble.init", body: "startCentral=\(startCentral)")
    if startCentral {
      ensureCentral()
    }
  }

  func requestBluetooth() {
    record(source: "ui", title: "request_bluetooth")
    ensureCentral()
    updateBluetoothState()
  }

  func startScan() {
    record(source: "ui", title: "scan.start.requested")
    startScan(reason: "manual", clearDiscovered: true)
  }

  func stopScan() {
    record(source: "ui", title: "scan.stop.requested")
    stopScan(reason: "manual")
  }

  func reconnectRemembered() {
    record(source: "ui", title: "reconnect_remembered.requested")
    ensureCentral()
    attemptAutomaticReconnect(reason: "manual")
  }

  func forgetRememberedDevice() {
    let previous = rememberedDeviceDescription
    defaults.removeObject(forKey: DefaultsKey.rememberedDeviceID)
    defaults.removeObject(forKey: DefaultsKey.rememberedDeviceName)
    rememberedDeviceID = nil
    rememberedDeviceName = nil
    autoReconnectTargetID = nil
    autoReconnectInFlight = false
    if activePeripheral == nil {
      activeDeviceIdentifier = nil
      activeDeviceName = "WHOOP strap"
    }
    updateRememberedDeviceDescription()
    updateReconnectState("forgotten")
    record(source: "ui", title: "remembered_device.forgotten", body: previous)
  }

  private func startScan(reason: String, clearDiscovered: Bool) {
    ensureCentral()
    guard let central, central.state == .poweredOn else {
      bluetoothState = "bluetooth unavailable"
      record(level: .warn, source: "ble", title: "scan.start.blocked", body: bluetoothState)
      return
    }
    if clearDiscovered {
      discoveredDevices = []
      peripherals = [:]
      selectedDeviceID = nil
    }
    isScanning = true
    central.scanForPeripherals(
      withServices: whoopServices,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
    record(source: "ble", title: "scan.started", body: "reason=\(reason) services=\(uuidList(whoopServices))")
  }

  private func stopScan(reason: String) {
    central?.stopScan()
    isScanning = false
    record(source: "ble", title: "scan.stopped", body: "reason=\(reason)")
  }

  func select(_ device: GooseDiscoveredDevice) {
    selectedDeviceID = device.id
    record(source: "ui", title: "device.selected", body: "\(device.name) \(device.id.uuidString)")
  }

  func connectSelected() {
    record(source: "ui", title: "connect.requested")
    ensureCentral()
    guard let central, central.state == .poweredOn else {
      connectionState = "bluetooth unavailable"
      record(level: .warn, source: "ble", title: "connect.blocked", body: connectionState)
      return
    }
    let deviceID = selectedDeviceID ?? discoveredDevices.first?.id
    guard let deviceID, let peripheral = peripherals[deviceID] else {
      connectionState = "no device selected"
      record(level: .warn, source: "ble", title: "connect.blocked", body: connectionState)
      return
    }
    stopScan(reason: "connect_selected")
    connect(peripheral, reason: "manual")
  }

  func sendClientHello() {
    record(source: "ui", title: "hello.send.requested")
    guard
      let activePeripheral,
      let commandCharacteristic,
      !GooseHello.clientHelloFrame.isEmpty
    else {
      connectionState = "hello blocked"
      record(level: .warn, source: "ble", title: "hello.blocked", body: "missing active peripheral or command characteristic")
      return
    }

    let writeType: CBCharacteristicWriteType
    if commandCharacteristic.properties.contains(.write) {
      writeType = .withResponse
    } else if commandCharacteristic.properties.contains(.writeWithoutResponse) {
      writeType = .withoutResponse
    } else {
      connectionState = "hello blocked"
      record(level: .warn, source: "ble", title: "hello.blocked", body: "Command characteristic is not writable")
      return
    }

    activePeripheral.writeValue(
      GooseHello.clientHelloFrame,
      for: commandCharacteristic,
      type: writeType
    )
    record(
      source: "ble",
      title: "hello.sent",
      body: "\(commandCharacteristic.uuid.uuidString) \(writeTypeName(writeType)) \(GooseHello.clientHelloFrameHex)"
    )
  }

  func syncHistoricalPackets() {
    record(source: "ui", title: "historical_sync.requested")
    beginHistoricalSync(trigger: "manual", automatic: false)
  }

#if DEBUG
  func previewHelloWorldToast() {
    record(source: "ui.debug", title: "toast.preview.requested", body: "Hello World")
    publishSyncToast(phase: .synced, titleOverride: "Hello World", detail: "Toast preview", clearAfter: 2.2)
  }
#endif

  func refreshBatteryLevel() {
    record(source: "ui", title: "battery.refresh.requested")
    guard let activePeripheral else {
      record(level: .warn, source: "ble.metadata", title: "battery.refresh.blocked", body: "no active peripheral")
      return
    }

    activePeripheral.delegate = self
    if let batteryLevelCharacteristic {
      readStandardValueIfPossible(activePeripheral, batteryLevelCharacteristic, reason: "view_appear")
      return
    }

    if let batteryService = activePeripheral.services?.first(where: { $0.uuid == batteryServiceID }) {
      if let characteristic = batteryService.characteristics?.first(where: { $0.uuid == batteryLevelCharacteristicID }) {
        batteryLevelCharacteristic = characteristic
        readStandardValueIfPossible(activePeripheral, characteristic, reason: "view_appear.cached_service")
      } else {
        record(source: "ble.metadata", title: "battery.discover_characteristic.requested", body: batteryService.uuid.uuidString)
        activePeripheral.discoverCharacteristics([batteryLevelCharacteristicID], for: batteryService)
      }
      return
    }

    record(source: "ble.metadata", title: "battery.discover_service.requested", body: batteryServiceID.uuidString)
    activePeripheral.discoverServices([batteryServiceID])
  }

  func recordLiveHeartRate(_ bpm: Int, source: String, at date: Date = Date()) {
    guard (20...240).contains(bpm) else {
      record(level: .warn, source: source, title: "heart_rate.rejected", body: "\(bpm) bpm outside expected range")
      return
    }
    liveHeartRateBPM = bpm
    liveHeartRateSource = source
    liveHeartRateUpdatedAt = date
    lastSyncAt = date
    record(source: source, title: "heart_rate.live", body: "\(bpm) bpm")
  }

  func record(
    level: GooseLogLevel = .info,
    source: String,
    title: String,
    body: String = ""
  ) {
    let message = GooseMessage(
      timestamp: Date(),
      level: level,
      source: source,
      title: title,
      body: body
    )
    messages.insert(message, at: 0)
    if messages.count > 200 {
      messages.removeLast(messages.count - 200)
    }
    writeOSLog(message)
  }

  private func ensureCentral() {
    if central == nil {
      record(source: "ble", title: "central.create")
      central = CBCentralManager(
        delegate: self,
        queue: .main,
        options: [
          CBCentralManagerOptionRestoreIdentifierKey: Self.restorationIdentifier,
        ]
      )
    }
  }

  private func updateBluetoothState() {
    let previous = bluetoothState
    switch central?.state {
    case .poweredOn:
      bluetoothState = "powered on"
    case .poweredOff:
      bluetoothState = "powered off"
    case .unauthorized:
      bluetoothState = "unauthorized"
    case .unsupported:
      bluetoothState = "unsupported"
    case .resetting:
      bluetoothState = "resetting"
    case .unknown:
      bluetoothState = "unknown"
    case nil:
      bluetoothState = "not requested"
    @unknown default:
      bluetoothState = "unknown"
    }
    if previous != bluetoothState {
      record(source: "ble", title: "bluetooth.state", body: bluetoothState)
    }
  }

  private func writeOSLog(_ message: GooseMessage) {
    let line = "\(message.source) \(message.title) \(message.body)"
    switch message.level {
    case .debug:
      logger.debug("\(line, privacy: .public)")
    case .info:
      logger.info("\(line, privacy: .public)")
    case .warn:
      logger.warning("\(line, privacy: .public)")
    case .error:
      logger.error("\(line, privacy: .public)")
    }
  }

  private func updateConnectionState(_ value: String) {
    let previous = connectionState
    connectionState = value
    if previous != value {
      record(source: "ble", title: "connection.state", body: value)
    }
  }

  private func updateReconnectState(_ value: String) {
    let previous = reconnectState
    reconnectState = value
    if previous != value {
      record(source: "ble", title: "reconnect.state", body: value)
    }
  }

  private var supportsV5HistoricalSync: Bool {
    commandCharacteristic?.uuid.uuidString.lowercased().hasPrefix("fd4b0002") == true
  }

  private func loadRememberedDevice() {
    rememberedDeviceName = defaults.string(forKey: DefaultsKey.rememberedDeviceName)
    if let idString = defaults.string(forKey: DefaultsKey.rememberedDeviceID) {
      rememberedDeviceID = UUID(uuidString: idString)
    }
    updateRememberedDeviceDescription()
  }

  private func updateRememberedDeviceDescription() {
    guard let rememberedDeviceID else {
      rememberedDeviceDescription = "none"
      return
    }
    if let rememberedDeviceName, !rememberedDeviceName.isEmpty {
      rememberedDeviceDescription = "\(rememberedDeviceName) \(rememberedDeviceID.uuidString)"
    } else {
      rememberedDeviceDescription = rememberedDeviceID.uuidString
    }
  }

  private func rememberPeripheral(_ peripheral: CBPeripheral, fallbackName: String? = nil) {
    let name = peripheral.name ?? fallbackName ?? rememberedDeviceName ?? "WHOOP"
    rememberedDeviceID = peripheral.identifier
    rememberedDeviceName = name
    updateActiveDevice(peripheral, fallbackName: name)
    defaults.set(peripheral.identifier.uuidString, forKey: DefaultsKey.rememberedDeviceID)
    defaults.set(name, forKey: DefaultsKey.rememberedDeviceName)
    updateRememberedDeviceDescription()
    record(source: "ble", title: "remembered_device.saved", body: rememberedDeviceDescription)
  }

  private func connect(_ peripheral: CBPeripheral, reason: String) {
    guard let central, central.state == .poweredOn else {
      updateConnectionState("bluetooth unavailable")
      updateReconnectState("blocked")
      record(level: .warn, source: "ble", title: "connect.blocked", body: "reason=\(reason) bluetooth unavailable")
      return
    }
    if activePeripheral?.identifier == peripheral.identifier,
       connectionState == "connecting" || connectionState == "discovering" || connectionState == "ready" {
      record(level: .debug, source: "ble", title: "connect.skipped", body: "already \(connectionState)")
      return
    }
    resetLiveDeviceFieldsIfNeeded(for: peripheral)
    updateActiveDevice(peripheral, fallbackName: discoveredName(for: peripheral.identifier))
    activePeripheral = peripheral
    peripheral.delegate = self
    updateConnectionState("connecting")
    updateReconnectState(reason.hasPrefix("auto") || reason == "restore" ? "connecting" : reconnectState)
    record(source: "ble", title: "connect.started", body: "reason=\(reason) \(peripheral.name ?? rememberedDeviceName ?? "WHOOP") \(peripheral.identifier.uuidString)")
    pendingConnectionReason = reason
    central.connect(
      peripheral,
      options: [
        CBConnectPeripheralOptionNotifyOnConnectionKey: true,
        CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
      ]
    )
  }

  private func attemptAutomaticReconnect(reason: String) {
    guard let central, central.state == .poweredOn else {
      updateReconnectState("waiting for bluetooth")
      return
    }
    guard activePeripheral == nil else {
      updateReconnectState("already connected")
      return
    }
    guard !autoReconnectInFlight else {
      record(level: .debug, source: "ble", title: "reconnect.skipped", body: "already in flight")
      return
    }

    if let rememberedDeviceID {
      updateReconnectState("retrieving remembered")
      autoReconnectInFlight = true
      let retrieved = central.retrievePeripherals(withIdentifiers: [rememberedDeviceID])
      if let peripheral = retrieved.first {
        peripherals[peripheral.identifier] = peripheral
        selectedDeviceID = peripheral.identifier
        connect(peripheral, reason: "auto.\(reason).remembered")
      } else {
        autoReconnectTargetID = rememberedDeviceID
        updateReconnectState("scanning for remembered")
        record(source: "ble", title: "reconnect.scan_fallback", body: rememberedDeviceID.uuidString)
        startScan(reason: "auto_reconnect", clearDiscovered: false)
      }
      return
    }

    let connected = central.retrieveConnectedPeripherals(
      withServices: whoopServices + [
        standardHeartRateServiceID,
        batteryServiceID,
        deviceInformationServiceID,
      ]
    )
    if let peripheral = connected.first {
      autoReconnectInFlight = true
      peripherals[peripheral.identifier] = peripheral
      selectedDeviceID = peripheral.identifier
      rememberPeripheral(peripheral)
      updateReconnectState("adopting connected peripheral")
      connect(peripheral, reason: "auto.\(reason).connected")
    } else {
      updateReconnectState("no remembered device")
    }
  }

  private func notificationCandidate(_ characteristic: CBCharacteristic) -> Bool {
    notificationCharacteristicIDs.contains(characteristic.uuid)
      || characteristic.uuid == standardHeartRateMeasurementID
  }

  private func standardReadableCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
    characteristic.uuid == batteryLevelCharacteristicID
      || characteristic.uuid == modelNumberCharacteristicID
      || characteristic.uuid == firmwareRevisionCharacteristicID
      || characteristic.uuid == hardwareRevisionCharacteristicID
      || characteristic.uuid == softwareRevisionCharacteristicID
      || characteristic.uuid == manufacturerNameCharacteristicID
  }

  private func readStandardValueIfPossible(
    _ peripheral: CBPeripheral,
    _ characteristic: CBCharacteristic,
    reason: String = "discovery"
  ) {
    guard standardReadableCharacteristic(characteristic) else {
      return
    }
    guard characteristic.properties.contains(.read) else {
      record(
        level: .debug,
        source: "ble",
        title: "metadata.read.skipped",
        body: "\(characteristic.uuid.uuidString) properties=\(propertyNames(characteristic.properties))"
      )
      return
    }
    peripheral.readValue(for: characteristic)
    record(source: "ble", title: "metadata.read.requested", body: "\(characteristic.uuid.uuidString) reason=\(reason)")
  }

  private func subscribeIfPossible(_ peripheral: CBPeripheral, _ characteristic: CBCharacteristic) {
    guard notificationCandidate(characteristic) else {
      return
    }
    guard characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else {
      record(
        level: .warn,
        source: "ble",
        title: "notify.blocked",
        body: "\(characteristic.uuid.uuidString) properties=\(propertyNames(characteristic.properties))"
      )
      return
    }
    peripheral.setNotifyValue(true, for: characteristic)
    record(source: "ble", title: "notify.requested", body: "\(characteristic.uuid.uuidString)")
  }

  private func scheduleAutomaticHistoricalSyncIfNeeded() {
    guard let reason = pendingAutomaticHistoricalSyncReason,
          connectionState == "ready",
          activePeripheral != nil,
          commandCharacteristic != nil,
          !isHistoricalSyncing else {
      return
    }

    readySyncWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else {
        return
      }
      guard self.pendingAutomaticHistoricalSyncReason == reason else {
        return
      }
      self.pendingAutomaticHistoricalSyncReason = nil
      self.beginHistoricalSync(trigger: reason, automatic: true)
    }
    readySyncWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    record(source: "ble.sync", title: "historical_sync.scheduled", body: reason)
  }

  private func beginHistoricalSync(trigger: String, automatic: Bool) {
    guard !isHistoricalSyncing else {
      record(level: .debug, source: "ble.sync", title: "historical_sync.skipped", body: "already syncing trigger=\(trigger)")
      return
    }
    guard activePeripheral != nil, commandCharacteristic != nil else {
      failHistoricalSync("Historical sync needs an active WHOOP command characteristic. Current connection state: \(connectionState).")
      return
    }
    guard connectionState == "ready" else {
      failHistoricalSync("Historical sync can only start from the ready state. Current connection state: \(connectionState).")
      return
    }
    guard supportsV5HistoricalSync else {
      let characteristic = commandCharacteristic?.uuid.uuidString ?? "missing"
      failHistoricalSync("Historical sync currently supports the Goose V5 fd4b command characteristic. Active command characteristic: \(characteristic).")
      return
    }

    historicalSyncRunID = UUID()
    isHistoricalSyncing = true
    historicalSyncStatus = "syncing"
    historicalPacketCount = 0
    historicalPacketsReceivedThisSync = 0
    historyEndAckQueued = false
    historyEndReceived = false
    historyCompleteReceived = false
    pendingHistoricalCommand = nil
    historicalCommandTimeoutWorkItem?.cancel()
    historicalIdleWorkItem?.cancel()
    publishSyncToast(phase: .syncing, detail: automatic ? "Fetching missed packets after reconnect" : "Fetching historical packets")
    record(source: "ble.sync", title: "historical_sync.started", body: "trigger=\(trigger)")
    writeHistoricalCommand(.getDataRange)
  }

  private func writeHistoricalCommand(_ kind: HistoricalCommandKind) {
    guard isHistoricalSyncing else {
      return
    }
    guard let activePeripheral, let commandCharacteristic else {
      failHistoricalSync("Lost the command characteristic before writing \(kind.name).")
      return
    }
    guard let writeType = writeType(for: commandCharacteristic) else {
      failHistoricalSync("Command characteristic \(commandCharacteristic.uuid.uuidString) is not writable for \(kind.name).")
      return
    }

    let sequence = nextHistoricalSequence()
    let frame = Self.buildV5CommandFrame(
      sequence: sequence,
      command: kind.commandNumber,
      data: kind.payload
    )
    pendingHistoricalCommand = PendingHistoricalCommand(kind: kind, sequence: sequence)
    scheduleHistoricalCommandTimeout(kind: kind, sequence: sequence)
    activePeripheral.writeValue(frame, for: commandCharacteristic, type: writeType)
    record(
      source: "ble.sync",
      title: "historical_sync.command.sent",
      body: "\(kind.name) seq=\(sequence) \(writeTypeName(writeType)) \(frame.hexString)"
    )
  }

  private func nextHistoricalSequence() -> UInt8 {
    let sequence = nextHistoricalCommandSequence
    nextHistoricalCommandSequence = nextHistoricalCommandSequence == UInt8.max ? 2 : nextHistoricalCommandSequence + 1
    return sequence
  }

  private func writeType(for characteristic: CBCharacteristic) -> CBCharacteristicWriteType? {
    if characteristic.properties.contains(.write) {
      return .withResponse
    }
    if characteristic.properties.contains(.writeWithoutResponse) {
      return .withoutResponse
    }
    return nil
  }

  private func scheduleHistoricalCommandTimeout(kind: HistoricalCommandKind, sequence: UInt8) {
    historicalCommandTimeoutWorkItem?.cancel()
    let runID = historicalSyncRunID
    let workItem = DispatchWorkItem { [weak self] in
      guard let self,
            self.historicalSyncRunID == runID,
            let pending = self.pendingHistoricalCommand,
            pending.kind.commandNumber == kind.commandNumber,
            pending.sequence == sequence else {
        return
      }
      self.failHistoricalSync("\(kind.name) timed out waiting for command response sequence \(sequence).")
    }
    historicalCommandTimeoutWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: workItem)
  }

  private func scheduleHistoricalIdleCompletion(reason: String) {
    historicalIdleWorkItem?.cancel()
    let runID = historicalSyncRunID
    let workItem = DispatchWorkItem { [weak self] in
      guard let self,
            self.historicalSyncRunID == runID,
            self.isHistoricalSyncing,
            self.pendingHistoricalCommand == nil else {
        return
      }
      if self.historyEndAckQueued {
        self.historyEndAckQueued = false
        self.writeHistoricalCommand(.historicalDataResult)
        return
      }
      self.completeHistoricalSync(reason: reason)
    }
    historicalIdleWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: workItem)
  }

  private func handleHistoricalSyncValue(_ value: Data, characteristic: CBCharacteristic) {
    guard isHistoricalSyncing else {
      return
    }
    for frame in Self.v5Frames(in: value) {
      handleHistoricalSyncFrame(frame, characteristic: characteristic)
    }
  }

  private func handleHistoricalSyncFrame(_ frame: Data, characteristic: CBCharacteristic) {
    guard let payload = Self.v5Payload(in: frame),
          let packetType = payload.first else {
      return
    }

    switch packetType {
    case V5PacketType.commandResponse, V5PacketType.puffinCommandResponse:
      handleHistoricalCommandResponse(payload)
    case V5PacketType.historicalData, V5PacketType.historicalIMUDataStream:
      historicalPacketsReceivedThisSync += 1
      historicalPacketCount = historicalPacketsReceivedThisSync
      scheduleHistoricalIdleCompletion(reason: "historical_data_idle")
      record(
        level: .debug,
        source: "ble.sync",
        title: "historical_sync.packet",
        body: "\(characteristic.uuid.uuidString) count=\(historicalPacketsReceivedThisSync)"
      )
    case V5PacketType.metadata, V5PacketType.puffinMetadata:
      handleHistoricalMetadata(payload)
    default:
      break
    }
  }

  private func handleHistoricalCommandResponse(_ payload: [UInt8]) {
    guard payload.count >= 5,
          let pending = pendingHistoricalCommand,
          payload[2] == pending.kind.commandNumber,
          payload[3] == pending.sequence else {
      return
    }

    historicalCommandTimeoutWorkItem?.cancel()
    pendingHistoricalCommand = nil
    let resultCode = payload[4]
    guard resultCode == 0 else {
      failHistoricalSync("\(pending.kind.name) returned result code \(resultCode) for sequence \(pending.sequence).")
      return
    }

    record(source: "ble.sync", title: "historical_sync.command.response", body: "\(pending.kind.name) seq=\(pending.sequence) ok")

    if historyEndAckQueued && pending.kind != .historicalDataResult {
      historyEndAckQueued = false
      writeHistoricalCommand(.historicalDataResult)
      return
    }

    switch pending.kind {
    case .getDataRange:
      writeHistoricalCommand(.sendHistoricalData)
    case .sendHistoricalData:
      scheduleHistoricalIdleCompletion(reason: "historical_transfer_idle")
    case .historicalDataResult:
      if historyCompleteReceived {
        completeHistoricalSync(reason: "history_complete")
      } else {
        scheduleHistoricalIdleCompletion(reason: "history_end_ack_idle")
      }
    }
  }

  private func handleHistoricalMetadata(_ payload: [UInt8]) {
    let rawKind: UInt16?
    if payload.first == V5PacketType.puffinMetadata {
      rawKind = payload.count >= 4 ? UInt16(payload[2]) | UInt16(payload[3]) << 8 : nil
    } else {
      rawKind = payload.count >= 3 ? UInt16(payload[2]) : nil
    }
    guard let rawKind, let kind = HistoricalMetadataKind(rawValue: rawKind) else {
      return
    }

    record(source: "ble.sync", title: "historical_sync.metadata", body: kind.name)
    scheduleHistoricalIdleCompletion(reason: "historical_metadata_idle")

    switch kind {
    case .historyStart:
      break
    case .historyEnd:
      historyEndReceived = true
      if pendingHistoricalCommand == nil {
        writeHistoricalCommand(.historicalDataResult)
      } else {
        historyEndAckQueued = true
      }
    case .historyComplete:
      historyCompleteReceived = true
      if pendingHistoricalCommand == nil && !historyEndAckQueued {
        completeHistoricalSync(reason: "history_complete")
      }
    }
  }

  private func completeHistoricalSync(reason: String) {
    historicalCommandTimeoutWorkItem?.cancel()
    historicalIdleWorkItem?.cancel()
    readySyncWorkItem?.cancel()
    pendingHistoricalCommand = nil
    historyEndAckQueued = false
    let completedAt = Date()
    isHistoricalSyncing = false
    historicalSyncStatus = "synced"
    lastHistoricalSyncCompletedAt = completedAt
    lastSyncAt = completedAt
    let detail = historicalPacketsReceivedThisSync == 0
      ? "No missed packets found"
      : "\(historicalPacketsReceivedThisSync) historical \(historicalPacketsReceivedThisSync == 1 ? "packet" : "packets") captured"
    publishSyncToast(phase: .synced, detail: detail, clearAfter: 2.2)
    record(source: "ble.sync", title: "historical_sync.completed", body: "reason=\(reason) \(detail)")
  }

  private func failHistoricalSync(_ message: String) {
    historicalCommandTimeoutWorkItem?.cancel()
    historicalIdleWorkItem?.cancel()
    readySyncWorkItem?.cancel()
    pendingHistoricalCommand = nil
    historyEndAckQueued = false
    isHistoricalSyncing = false
    historicalSyncStatus = "failed"
    let failure = GooseSyncFailure(title: "Sync Failed", message: message, occurredAt: Date())
    lastSyncFailure = failure
    syncFailureSheet = failure
    publishSyncToast(phase: .failed, detail: "Tap for details", clearAfter: 4.5)
    record(level: .error, source: "ble.sync", title: "historical_sync.failed", body: message)
  }

  private func publishSyncToast(
    phase: GooseSyncToastPhase,
    titleOverride: String? = nil,
    detail: String,
    clearAfter: TimeInterval? = nil
  ) {
    syncClearWorkItem?.cancel()
    let title: String
    switch phase {
    case .syncing:
      title = "Syncing"
    case .synced:
      title = "Synced"
    case .failed:
      title = "Sync Failed"
    }
    syncToast = GooseSyncToast(phase: phase, title: titleOverride ?? title, detail: detail)
    guard let clearAfter else {
      return
    }
    let toastID = syncToast?.id
    let workItem = DispatchWorkItem { [weak self] in
      guard self?.syncToast?.id == toastID else {
        return
      }
      self?.syncToast = nil
    }
    syncClearWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + clearAfter, execute: workItem)
  }

  private func handleStandardHeartRate(_ value: Data, characteristic: CBCharacteristic) {
    guard let bpm = Self.parseStandardHeartRateMeasurement(value) else {
      record(level: .warn, source: "ble.hr.standard", title: "heart_rate.parse_failed", body: value.hexString)
      return
    }
    recordLiveHeartRate(bpm, source: "ble.hr.standard")
  }

  @discardableResult
  private func handleStandardReadValue(
    _ value: Data,
    characteristic: CBCharacteristic,
    capturedAt: Date
  ) -> Bool {
    switch characteristic.uuid {
    case batteryLevelCharacteristicID:
      guard let raw = value.first else {
        record(level: .warn, source: "ble.metadata", title: "battery.read.empty")
        return true
      }
      batteryLevelPercent = min(max(Int(raw), 0), 100)
      batteryUpdatedAt = capturedAt
      lastSyncAt = capturedAt
      record(source: "ble.metadata", title: "battery.read", body: "\(batteryLevelPercent ?? 0)%")
      return true
    case modelNumberCharacteristicID:
      modelNumber = decodedMetadataString(value)
    case firmwareRevisionCharacteristicID:
      firmwareVersion = decodedMetadataString(value)
    case hardwareRevisionCharacteristicID:
      hardwareRevision = decodedMetadataString(value)
    case softwareRevisionCharacteristicID:
      softwareRevision = decodedMetadataString(value)
    case manufacturerNameCharacteristicID:
      manufacturerName = decodedMetadataString(value)
    default:
      return false
    }

    lastSyncAt = capturedAt
    let stringValue = decodedMetadataString(value) ?? value.hexString
    record(source: "ble.metadata", title: "device_info.read", body: "\(characteristic.uuid.uuidString)=\(stringValue)")
    return true
  }

  private func decodedMetadataString(_ data: Data) -> String? {
    var trimSet = CharacterSet.whitespacesAndNewlines
    trimSet.formUnion(.controlCharacters)
    guard let string = String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: trimSet),
      !string.isEmpty
    else {
      return nil
    }
    return string
  }

  private func discoveredName(for id: UUID) -> String? {
    discoveredDevices.first { $0.id == id }?.name
  }

  private func updateActiveDevice(_ peripheral: CBPeripheral, fallbackName: String? = nil) {
    activeDeviceIdentifier = peripheral.identifier
    activeDeviceName = peripheral.name ?? fallbackName ?? rememberedDeviceName ?? "WHOOP strap"
  }

  private func resetLiveDeviceFieldsIfNeeded(for peripheral: CBPeripheral) {
    guard activeDeviceIdentifier != peripheral.identifier else {
      return
    }
    batteryLevelCharacteristic = nil
    batteryLevelPercent = nil
    batteryUpdatedAt = nil
    firmwareVersion = nil
    modelNumber = nil
    hardwareRevision = nil
    softwareRevision = nil
    manufacturerName = nil
    historicalSyncStatus = "idle"
    historicalPacketCount = 0
    liveHeartRateBPM = nil
    liveHeartRateSource = "waiting"
    liveHeartRateUpdatedAt = nil
    connectedAt = nil
    lastSyncAt = nil
  }

  private static func parseStandardHeartRateMeasurement(_ value: Data) -> Int? {
    guard value.count >= 2 else {
      return nil
    }
    let flags = value[0]
    if flags & 0x01 == 0 {
      return Int(value[1])
    }
    guard value.count >= 3 else {
      return nil
    }
    return Int(UInt16(value[1]) | UInt16(value[2]) << 8)
  }

  private func uuidList(_ uuids: [CBUUID]) -> String {
    uuids.map(\.uuidString).joined(separator: ",")
  }

  private func propertyNames(_ properties: CBCharacteristicProperties) -> String {
    var names: [String] = []
    if properties.contains(.read) { names.append("read") }
    if properties.contains(.write) { names.append("write") }
    if properties.contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }
    if properties.contains(.notify) { names.append("notify") }
    if properties.contains(.indicate) { names.append("indicate") }
    if properties.contains(.broadcast) { names.append("broadcast") }
    if properties.contains(.authenticatedSignedWrites) { names.append("authenticatedSignedWrites") }
    if properties.contains(.extendedProperties) { names.append("extendedProperties") }
    return names.isEmpty ? "none" : names.joined(separator: ",")
  }

  private func writeTypeName(_ writeType: CBCharacteristicWriteType) -> String {
    switch writeType {
    case .withResponse:
      return "withResponse"
    case .withoutResponse:
      return "withoutResponse"
    @unknown default:
      return "unknown"
    }
  }

  private static func v5Frames(in data: Data) -> [Data] {
    var bytes = Array(data)
    var frames: [Data] = []
    while let startIndex = bytes.firstIndex(of: 0xaa) {
      if startIndex > 0 {
        bytes.removeFirst(startIndex)
      }
      guard bytes.count >= 8 else {
        break
      }
      let declaredLength = Int(UInt16(bytes[2]) | UInt16(bytes[3]) << 8)
      guard declaredLength >= 4 else {
        bytes.removeFirst()
        continue
      }
      let expectedLength = declaredLength + 8
      guard bytes.count >= expectedLength else {
        break
      }
      frames.append(Data(bytes[0..<expectedLength]))
      bytes.removeFirst(expectedLength)
    }
    return frames
  }

  private static func v5Payload(in frame: Data) -> [UInt8]? {
    let bytes = Array(frame)
    guard bytes.count >= 12 else {
      return nil
    }
    let declaredLength = Int(UInt16(bytes[2]) | UInt16(bytes[3]) << 8)
    let expectedLength = declaredLength + 8
    guard bytes.count == expectedLength, declaredLength >= 4 else {
      return nil
    }
    return Array(bytes[8..<(bytes.count - 4)])
  }

  private static func buildV5CommandFrame(sequence: UInt8, command: UInt8, data: [UInt8]) -> Data {
    var payload = [V5PacketType.command, sequence, command]
    payload.append(contentsOf: data)
    let padding = payload.count % 4 == 0 ? 0 : 4 - payload.count % 4
    if padding > 0 {
      payload.append(contentsOf: repeatElement(UInt8(0), count: padding))
    }

    let payloadCRC = crc32(payload)
    let declaredLength = UInt16(payload.count + 4)
    var frame: [UInt8] = [
      0xaa,
      0x01,
      UInt8(declaredLength & 0xff),
      UInt8((declaredLength >> 8) & 0xff),
      0x00,
      0x01,
    ]
    let headerCRC = crc16Modbus(frame)
    frame.append(UInt8(headerCRC & 0xff))
    frame.append(UInt8((headerCRC >> 8) & 0xff))
    frame.append(contentsOf: payload)
    frame.append(UInt8(payloadCRC & 0xff))
    frame.append(UInt8((payloadCRC >> 8) & 0xff))
    frame.append(UInt8((payloadCRC >> 16) & 0xff))
    frame.append(UInt8((payloadCRC >> 24) & 0xff))
    return Data(frame)
  }

  private static func crc16Modbus(_ bytes: [UInt8]) -> UInt16 {
    var crc = UInt16(0xffff)
    for byte in bytes {
      crc ^= UInt16(byte)
      for _ in 0..<8 {
        if crc & 1 == 1 {
          crc = (crc >> 1) ^ 0xa001
        } else {
          crc >>= 1
        }
      }
    }
    return crc
  }

  private static func crc32(_ bytes: [UInt8]) -> UInt32 {
    var crc = UInt32(0xffffffff)
    for byte in bytes {
      crc ^= UInt32(byte)
      for _ in 0..<8 {
        if crc & 1 == 1 {
          crc = (crc >> 1) ^ 0xedb88320
        } else {
          crc >>= 1
        }
      }
    }
    return ~crc
  }
}

extension GooseBLEClient: CBCentralManagerDelegate {
  func centralManager(
    _ central: CBCentralManager,
    willRestoreState dict: [String: Any]
  ) {
    let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
    record(source: "ble", title: "central.restore_state", body: "peripherals=\(restored.count)")
    guard let peripheral = restored.first else {
      updateReconnectState("restore empty")
      return
    }
    peripherals[peripheral.identifier] = peripheral
    selectedDeviceID = peripheral.identifier
    activePeripheral = peripheral
    peripheral.delegate = self
    rememberPeripheral(peripheral)
    pendingAutomaticHistoricalSyncReason = "restore"
    updateReconnectState("restored")
    switch peripheral.state {
    case .connected:
      let now = Date()
      connectedAt = now
      lastSyncAt = now
      updateConnectionState("discovering")
      peripheral.discoverServices(nil)
    case .connecting:
      updateConnectionState("connecting")
    case .disconnected, .disconnecting:
      if central.state == .poweredOn {
        connect(peripheral, reason: "restore")
      }
    @unknown default:
      if central.state == .poweredOn {
        connect(peripheral, reason: "restore")
      }
    }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    updateBluetoothState()
    if central.state == .poweredOn {
      if !startupReconnectAttempted {
        startupReconnectAttempted = true
        attemptAutomaticReconnect(reason: "startup")
      }
    } else {
      isScanning = false
      if isHistoricalSyncing {
        failHistoricalSync("Bluetooth became unavailable during historical sync. State: \(bluetoothState).")
      }
      updateConnectionState("disconnected")
      updateReconnectState("waiting for bluetooth")
      connectedAt = nil
    }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    peripherals[peripheral.identifier] = peripheral
    let name = peripheral.name
      ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
      ?? "WHOOP"
    let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
      .map(\.uuidString)
      .joined(separator: ",")
    let device = GooseDiscoveredDevice(
      id: peripheral.identifier,
      name: name,
      rssi: RSSI.intValue
    )

    discoveredDevices.removeAll { $0.id == device.id }
    discoveredDevices.append(device)
    discoveredDevices.sort { $0.rssi > $1.rssi }
    selectedDeviceID = selectedDeviceID ?? device.id
    record(
      source: "ble",
      title: "device.discovered",
      body: "\(name) id=\(device.id.uuidString) rssi=\(device.rssi) services=\(serviceUUIDs)"
    )

    if autoReconnectTargetID == peripheral.identifier {
      record(source: "ble", title: "reconnect.scan_match", body: peripheral.identifier.uuidString)
      autoReconnectTargetID = nil
      stopScan(reason: "auto_reconnect_match")
      connect(peripheral, reason: "auto.scan")
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    activePeripheral = peripheral
    peripheral.delegate = self
    autoReconnectInFlight = false
    autoReconnectTargetID = nil
    let reason = pendingConnectionReason ?? "unknown"
    pendingConnectionReason = nil
    if reason.hasPrefix("auto.") || reason == "restore" {
      pendingAutomaticHistoricalSyncReason = reason
    }
    rememberPeripheral(
      peripheral,
      fallbackName: discoveredDevices.first { $0.id == peripheral.identifier }?.name
    )
    let now = Date()
    connectedAt = now
    lastSyncAt = now
    updateConnectionState("discovering")
    updateReconnectState("connected")
    record(source: "ble", title: "connect.succeeded", body: "\(peripheral.name ?? "WHOOP") \(peripheral.identifier.uuidString)")
    peripheral.discoverServices(nil)
  }

  func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    autoReconnectInFlight = false
    pendingConnectionReason = nil
    updateConnectionState("connect failed")
    updateReconnectState("connect failed")
    record(level: .error, source: "ble", title: "connect.failed", body: error?.localizedDescription ?? "unknown")
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    let shouldReconnect = rememberedDeviceID == peripheral.identifier
    autoReconnectInFlight = false
    readySyncWorkItem?.cancel()
    if isHistoricalSyncing {
      failHistoricalSync("WHOOP disconnected during historical sync. \(error?.localizedDescription ?? "No CoreBluetooth error was provided.")")
    }
    updateConnectionState(error?.localizedDescription ?? "disconnected")
    record(
      level: error == nil ? .info : .warn,
      source: "ble",
      title: "disconnect",
      body: error?.localizedDescription ?? peripheral.identifier.uuidString
    )
    activePeripheral = nil
    commandCharacteristic = nil
    batteryLevelCharacteristic = nil
    connectedAt = nil
    if shouldReconnect {
      pendingAutomaticHistoricalSyncReason = "auto.disconnect"
      updateReconnectState("reconnecting after disconnect")
      connect(peripheral, reason: "auto.disconnect")
    }
  }
}

extension GooseBLEClient: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let error {
      updateConnectionState(error.localizedDescription)
      record(level: .error, source: "ble", title: "gatt.services.failed", body: error.localizedDescription)
      return
    }
    let services = peripheral.services ?? []
    record(source: "ble", title: "gatt.services", body: uuidList(services.map(\.uuid)))
    for service in services {
      peripheral.discoverCharacteristics(nil, for: service)
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    if let error {
      updateConnectionState(error.localizedDescription)
      record(level: .error, source: "ble", title: "gatt.characteristics.failed", body: "\(service.uuid.uuidString) \(error.localizedDescription)")
      return
    }

    let characteristics = service.characteristics ?? []
    let characteristicSummary = characteristics
      .map { "\($0.uuid.uuidString)[\(propertyNames($0.properties))]" }
      .joined(separator: ",")
    record(source: "ble", title: "gatt.characteristics", body: "\(service.uuid.uuidString) \(characteristicSummary)")

    for characteristic in characteristics {
      if commandCharacteristicIDs.contains(characteristic.uuid) {
        commandCharacteristic = characteristic
        record(
          source: "ble",
          title: "command_characteristic.discovered",
          body: "\(service.uuid.uuidString) \(characteristic.uuid.uuidString) properties=\(propertyNames(characteristic.properties))"
        )
      }
      if characteristic.uuid == batteryLevelCharacteristicID {
        batteryLevelCharacteristic = characteristic
        record(
          source: "ble.metadata",
          title: "battery_characteristic.discovered",
          body: "\(service.uuid.uuidString) properties=\(propertyNames(characteristic.properties))"
        )
      }
      subscribeIfPossible(peripheral, characteristic)
      readStandardValueIfPossible(peripheral, characteristic)
    }

    if commandCharacteristic != nil {
      updateConnectionState("ready")
      scheduleAutomaticHistoricalSyncIfNeeded()
    } else if connectionState == "discovering" {
      updateConnectionState("connected")
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    let capturedAt = Date()
    let readValue = standardReadableCharacteristic(characteristic)
    if let error {
      record(
        level: .error,
        source: "ble",
        title: readValue ? "metadata.read.failed" : "notification.error",
        body: error.localizedDescription
      )
      return
    }
    guard let value = characteristic.value else {
      record(
        level: .warn,
        source: "ble",
        title: readValue ? "metadata.read.empty" : "notification.empty",
        body: characteristic.uuid.uuidString
      )
      return
    }
    if handleStandardReadValue(value, characteristic: characteristic, capturedAt: capturedAt) {
      return
    }
    handleHistoricalSyncValue(value, characteristic: characteristic)

    let event = GooseNotificationEvent(
      deviceID: peripheral.identifier,
      serviceUUID: characteristic.service?.uuid.uuidString ?? "",
      characteristicUUID: characteristic.uuid.uuidString,
      value: value,
      capturedAt: capturedAt
    )
    lastSyncAt = event.capturedAt
    record(
      level: .debug,
      source: "ble",
      title: "notification.received",
      body: "\(event.characteristicUUID) bytes=\(value.count) hex=\(value.hexString)"
    )

    if characteristic.uuid == standardHeartRateMeasurementID {
      handleStandardHeartRate(value, characteristic: characteristic)
    }
    onNotification?(event)
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didWriteValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    if let error {
      record(level: .error, source: "ble", title: "write.failed", body: "\(characteristic.uuid.uuidString) \(error.localizedDescription)")
      if isHistoricalSyncing && characteristic.uuid == commandCharacteristic?.uuid {
        failHistoricalSync("Write to \(characteristic.uuid.uuidString) failed during historical sync: \(error.localizedDescription)")
      }
    } else {
      record(source: "ble", title: "write.accepted", body: characteristic.uuid.uuidString)
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    if let error {
      record(level: .error, source: "ble", title: "notify.failed", body: "\(characteristic.uuid.uuidString) \(error.localizedDescription)")
    } else {
      let state = characteristic.isNotifying ? "subscribed" : "unsubscribed"
      record(source: "ble", title: "notify.state", body: "\(characteristic.uuid.uuidString) \(state)")
    }
  }
}
