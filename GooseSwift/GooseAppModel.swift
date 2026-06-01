import Foundation

@MainActor
final class GooseAppModel: ObservableObject {
  @Published var onboardingComplete = false
  @Published var rustStatus = "Rust bridge not checked"
  @Published var helloSummary = "Client hello not prepared"
  @Published var lastParsedFrameSummary = "No notification frames parsed"

  let ble: GooseBLEClient
  let activitySession = ActivitySessionModel()
  let activityLocationTracker = ActivityLocationTracker()
  private let rust = GooseRustBridge()

  init(startBLE: Bool = true) {
    ble = GooseBLEClient(startCentral: startBLE)
    ble.onNotification = { [weak self] event in
      Task { @MainActor in
        self?.handleNotification(event)
      }
    }
    ble.record(source: "app", title: "model.init")
    prepareClientHello()
  }

  func completeOnboarding() {
    onboardingComplete = true
    ble.record(source: "ui", title: "onboarding.complete")
  }

  func recordUIAction(_ title: String, detail: String = "") {
    ble.record(source: "ui", title: title, body: detail)
  }

  func prepareClientHello() {
    ble.record(source: "rust", title: "hello.prepare.start")
    do {
      let version = try rust.request(method: "core.version")
      let coreVersion = (version["core_version"] as? String) ?? "unknown"
      rustStatus = "Rust core \(coreVersion)"
      ble.record(source: "rust", title: "core.version", body: coreVersion)

      let parsed = try rust.request(
        method: "protocol.parse_frame_hex",
        args: [
          "device_type": "GOOSE",
          "frame_hex": GooseHello.clientHelloFrameHex,
        ]
      )
      let sequence = parsed["sequence"] ?? "?"
      let packetType = parsed["packet_type"] ?? "?"
      helloSummary = "GET_HELLO seq \(sequence), packet \(packetType)"
      ble.record(source: "rust", title: "hello.prepare.ok", body: helloSummary)
    } catch {
      rustStatus = "Rust bridge unavailable"
      helloSummary = "Client hello frame ready; parser unavailable"
      ble.record(level: .error, source: "rust", title: "hello.prepare.failed", body: String(describing: error))
    }
  }

  private func handleNotification(_ event: GooseNotificationEvent) {
    let frames = gooseFrames(in: event.value, deviceType: event.rustDeviceType)
    guard !frames.isEmpty else {
      let prefix = Data(event.value.prefix(8)).hexString
      ble.record(
        level: .debug,
        source: "rust",
        title: "notification.parser.skipped",
        body: "\(event.characteristicUUID) no complete \(event.rustDeviceType) frame prefix=\(prefix)"
      )
      return
    }

    for frame in frames {
      parseNotificationFrame(frame, event: event)
    }
  }

  private func parseNotificationFrame(_ frame: Data, event: GooseNotificationEvent) {
    do {
      let parsed = try rust.request(
        method: "protocol.parse_frame_hex",
        args: [
          "device_type": event.rustDeviceType,
          "frame_hex": frame.hexString,
        ]
      )
      let summary = frameSummary(parsed)
      lastParsedFrameSummary = summary
      ble.record(source: "rust", title: "notification.frame.parsed", body: summary)

      if let bpm = extractHeartRate(from: parsed) {
        ble.recordLiveHeartRate(bpm, source: "rust.k10")
      }
    } catch {
      ble.record(
        level: .warn,
        source: "rust",
        title: "notification.frame.parse_failed",
        body: "\(event.characteristicUUID) \(String(describing: error))"
      )
    }
  }

  private func gooseFrames(in data: Data, deviceType: String) -> [Data] {
    var bytes = Array(data)
    var frames: [Data] = []
    let headerLength = deviceType == "GEN4" ? 4 : 8

    while let startIndex = bytes.firstIndex(of: 0xaa) {
      if startIndex > 0 {
        bytes.removeFirst(startIndex)
      }
      guard bytes.count >= headerLength else {
        break
      }

      let declaredLength: Int
      if deviceType == "GEN4" {
        declaredLength = Int(bytes[1]) | Int(bytes[2]) << 8
      } else {
        declaredLength = Int(bytes[2]) | Int(bytes[3]) << 8
      }
      guard declaredLength >= 4 else {
        bytes.removeFirst()
        continue
      }

      let expectedLength = declaredLength + headerLength
      guard bytes.count >= expectedLength else {
        break
      }
      frames.append(Data(bytes[0..<expectedLength]))
      bytes.removeFirst(expectedLength)
    }

    return frames
  }

  private func frameSummary(_ parsed: [String: Any]) -> String {
    let packet = intString(parsed["packet_type"])
    let packetName = parsed["packet_type_name"] as? String ?? "unknown"
    let sequence = intString(parsed["sequence"])
    let warnings = (parsed["warnings"] as? [Any])?.count ?? 0
    guard let payload = parsed["parsed_payload"] as? [String: Any] else {
      return "packet=\(packetName)(\(packet)) seq=\(sequence) warnings=\(warnings)"
    }

    let kind = payload["kind"] as? String ?? "unknown"
    if kind == "data_packet" {
      let packetK = intString(payload["packet_k"])
      let domain = payload["domain"] as? String ?? "unknown"
      let body = (payload["body_summary"] as? [String: Any])?["kind"] as? String ?? "none"
      return "packet=\(packetName)(\(packet)) seq=\(sequence) data.k=\(packetK) domain=\(domain) body=\(body) warnings=\(warnings)"
    }

    return "packet=\(packetName)(\(packet)) seq=\(sequence) payload=\(kind) warnings=\(warnings)"
  }

  private func extractHeartRate(from parsed: [String: Any]) -> Int? {
    guard
      let payload = parsed["parsed_payload"] as? [String: Any],
      payload["kind"] as? String == "data_packet",
      let body = payload["body_summary"] as? [String: Any],
      body["kind"] as? String == "raw_motion_k10"
    else {
      return nil
    }
    return intValue(body["heart_rate"])
  }

  private func intString(_ value: Any?) -> String {
    intValue(value).map(String.init) ?? "?"
  }

  private func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int {
      return int
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let string = value as? String {
      return Int(string)
    }
    return nil
  }
}
