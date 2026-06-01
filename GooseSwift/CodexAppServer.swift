import Combine
import Foundation

struct CodexAppServerBundleStatus: Equatable {
  let resourceURL: URL?
  let binaryURL: URL?
  let manifestURL: URL?
  let isBundlePresent: Bool
  let isBinaryPresent: Bool
  let canExecuteBundledServer: Bool
  let platformMessage: String

  var title: String {
    if canExecuteBundledServer {
      return "Ready for local app-server"
    }
    if isBundlePresent {
      return "Bundle staged, execution unavailable"
    }
    return "Codex app-server not staged"
  }
}

enum CodexAppServerRunState: Equatable {
  case idle
  case unavailable(String)
  case ready(CodexAppServerBundleStatus)
  case running(endpoint: String)
  case failed(String)

  var displayTitle: String {
    switch self {
    case .idle:
      return "Not checked"
    case .unavailable:
      return "Unavailable"
    case .ready:
      return "Ready"
    case .running:
      return "Running"
    case .failed:
      return "Failed"
    }
  }

  var displayDetail: String {
    switch self {
    case .idle:
      return "Refresh to inspect the bundled app-server."
    case .unavailable(let message):
      return message
    case .ready(let status):
      return status.platformMessage
    case .running(let endpoint):
      return endpoint
    case .failed(let message):
      return message
    }
  }
}

enum CodexAppServerConnectionState: Equatable {
  case disconnected
  case connecting(String)
  case connected(String)
  case failed(String)

  var title: String {
    switch self {
    case .disconnected:
      return "Disconnected"
    case .connecting:
      return "Connecting"
    case .connected:
      return "Connected"
    case .failed:
      return "Failed"
    }
  }

  var detail: String {
    switch self {
    case .disconnected:
      return "Start `codex app-server` on the Mac, then connect from the simulator."
    case .connecting(let endpoint), .connected(let endpoint):
      return endpoint
    case .failed(let message):
      return message
    }
  }
}

struct CodexAuthWebPresentation: Identifiable, Equatable {
  let id: String
  let url: URL
}

struct CodexLoginDeviceCode: Equatable {
  let loginID: String
  let verificationURL: URL
  let userCode: String
}

struct CodexAppServerMessage: Identifiable, Equatable {
  enum Level: Equatable {
    case info
    case success
    case warning
    case error
  }

  let id = UUID()
  let timestamp = Date()
  let level: Level
  let title: String
  let detail: String
}

@MainActor
final class CodexAppServerModel: ObservableObject {
  @Published private(set) var bundleStatus: CodexAppServerBundleStatus
  @Published private(set) var runState: CodexAppServerRunState
  @Published private(set) var connectionState: CodexAppServerConnectionState = .disconnected
  @Published private(set) var loginStatus = "Not signed in"
  @Published private(set) var loginID: String?
  @Published private(set) var authWebPresentation: CodexAuthWebPresentation?
  @Published private(set) var deviceCode: CodexLoginDeviceCode?
  @Published private(set) var messages: [CodexAppServerMessage] = []

  private let inspector: CodexAppServerBundleInspecting
  private let launcher: CodexAppServerLaunching
  private var rpcClient: CodexAppServerRPCClient?

  init(
    inspector: CodexAppServerBundleInspecting = BundleCodexAppServerInspector(),
    launcher: CodexAppServerLaunching = PlatformCodexAppServerLauncher()
  ) {
    self.inspector = inspector
    self.launcher = launcher
    let status = inspector.inspect()
    bundleStatus = status
    runState = status.isBundlePresent ? .ready(status) : .unavailable(status.platformMessage)
  }

  func refresh() {
    let status = inspector.inspect()
    bundleStatus = status
    runState = status.isBundlePresent ? .ready(status) : .unavailable(status.platformMessage)
  }

  func start() {
    let status = inspector.inspect()
    bundleStatus = status

    guard status.isBundlePresent else {
      runState = .unavailable(status.platformMessage)
      return
    }
    guard status.canExecuteBundledServer else {
      runState = .unavailable(status.platformMessage)
      return
    }

    do {
      let endpoint = try launcher.start(bundleStatus: status)
      runState = .running(endpoint: endpoint)
    } catch {
      runState = .failed(describe(error))
    }
  }

  func connect(endpointText: String) {
    Task {
      _ = await connectIfNeeded(endpointText: endpointText)
    }
  }

  func disconnect() {
    rpcClient?.disconnect()
    rpcClient = nil
    connectionState = .disconnected
    appendMessage(level: .info, title: "Disconnected", detail: "Closed the Codex app-server WebSocket.")
  }

  func startChatGPTLogin(endpointText: String) {
    Task {
      guard let client = await connectIfNeeded(endpointText: endpointText) else {
        return
      }

      loginStatus = "Starting ChatGPT login"
      appendMessage(level: .info, title: "Login request", detail: "Requesting Codex-managed ChatGPT OAuth.")

      do {
        let response = try await client.sendRequest(
          method: "account/login/start",
          params: [
            "type": "chatgpt",
            "codexStreamlinedLogin": true,
          ]
        )
        handleLoginStartResponse(response)
      } catch {
        loginStatus = "Login request failed"
        appendMessage(level: .error, title: "Login request failed", detail: describe(error))
      }
    }
  }

  func handleAuthWebEvent(_ event: CodexAuthWebEvent) {
    switch event {
    case .didStart(let url):
      appendMessage(level: .info, title: "Auth page loading", detail: url.absoluteString)
    case .didFinish(let url):
      appendMessage(level: .info, title: "Auth page loaded", detail: url.absoluteString)
    case .didFail(let message):
      appendMessage(level: .error, title: "Auth page failed", detail: message)
    case .callback(let url):
      appendMessage(level: .success, title: "Auth callback received", detail: url.absoluteString)
      authWebPresentation = nil
    case .scriptMessage(let message):
      appendMessage(level: .info, title: "Auth page message", detail: message)
    }
  }

  func handleOpenURL(_ url: URL) {
    appendMessage(level: .success, title: "App callback received", detail: url.absoluteString)
    authWebPresentation = nil
  }

  func dismissAuthWebView() {
    authWebPresentation = nil
  }

  private func connectIfNeeded(endpointText: String) async -> CodexAppServerRPCClient? {
    if let client = rpcClient, connectionState.isConnected {
      return client
    }

    do {
      let endpoint = try normalizeEndpoint(endpointText)
      connectionState = .connecting(endpoint.absoluteString)
      appendMessage(level: .info, title: "Connecting", detail: endpoint.absoluteString)

      let client = CodexAppServerRPCClient { [weak self] event in
        self?.handleRPCEvent(event)
      }
      rpcClient = client
      try await client.connect(to: endpoint)

      connectionState = .connected(endpoint.absoluteString)
      appendMessage(level: .success, title: "Connected", detail: endpoint.absoluteString)
      return client
    } catch {
      rpcClient?.disconnect()
      rpcClient = nil
      connectionState = .failed(describe(error))
      appendMessage(level: .error, title: "Connection failed", detail: describe(error))
      return nil
    }
  }

  private func handleLoginStartResponse(_ response: Any) {
    guard let payload = response as? [String: Any], let type = payload["type"] as? String else {
      loginStatus = "Unexpected login response"
      appendMessage(level: .error, title: "Unexpected login response", detail: describeJSON(response))
      return
    }

    switch type {
    case "chatgpt":
      guard
        let authURLText = payload["authUrl"] as? String,
        let authURL = URL(string: authURLText),
        let loginID = payload["loginId"] as? String
      else {
        loginStatus = "Incomplete ChatGPT login response"
        appendMessage(level: .error, title: "Incomplete login response", detail: describeJSON(payload))
        return
      }

      self.loginID = loginID
      deviceCode = nil
      authWebPresentation = CodexAuthWebPresentation(id: loginID, url: authURL)
      loginStatus = "Waiting for ChatGPT OAuth"
      appendMessage(level: .success, title: "Auth URL ready", detail: authURL.absoluteString)

    case "chatgptDeviceCode":
      guard
        let verificationURLText = payload["verificationUrl"] as? String,
        let verificationURL = URL(string: verificationURLText),
        let userCode = payload["userCode"] as? String,
        let loginID = payload["loginId"] as? String
      else {
        loginStatus = "Incomplete device-code response"
        appendMessage(level: .error, title: "Incomplete device-code response", detail: describeJSON(payload))
        return
      }

      self.loginID = loginID
      authWebPresentation = nil
      deviceCode = CodexLoginDeviceCode(loginID: loginID, verificationURL: verificationURL, userCode: userCode)
      loginStatus = "Waiting for device-code approval"
      appendMessage(level: .success, title: "Device-code login ready", detail: "\(verificationURL.absoluteString) code \(userCode)")

    default:
      loginStatus = "Unsupported login response"
      appendMessage(level: .warning, title: "Unsupported login response", detail: type)
    }
  }

  private func handleRPCEvent(_ event: CodexAppServerRPCEvent) {
    switch event {
    case .notification(let method, let params):
      handleNotification(method: method, params: params)
    case .closed(let message):
      rpcClient = nil
      connectionState = .disconnected
      appendMessage(level: .warning, title: "Connection closed", detail: message)
    case .rawMessage(let message):
      appendMessage(level: .info, title: "Server message", detail: message)
    }
  }

  private func handleNotification(method: String, params: [String: Any]) {
    switch method {
    case "account/login/completed":
      let success = params["success"] as? Bool ?? false
      let error = params["error"] as? String
      let completedLoginID = params["loginId"] as? String

      if success {
        loginID = completedLoginID ?? loginID
        loginStatus = "Signed in with ChatGPT"
        authWebPresentation = nil
        deviceCode = nil
        appendMessage(level: .success, title: "Login completed", detail: completedLoginID ?? "Codex account is ready.")
      } else {
        loginStatus = "Login failed"
        appendMessage(level: .error, title: "Login failed", detail: error ?? "Codex did not include an error.")
      }

    case "account/updated":
      appendMessage(level: .success, title: "Account updated", detail: describeJSON(params))

    default:
      appendMessage(level: .info, title: method, detail: describeJSON(params))
    }
  }

  private func appendMessage(level: CodexAppServerMessage.Level, title: String, detail: String) {
    messages.insert(
      CodexAppServerMessage(level: level, title: title, detail: detail),
      at: 0
    )
    if messages.count > 40 {
      messages.removeLast(messages.count - 40)
    }
  }

  private func normalizeEndpoint(_ endpointText: String) throws -> URL {
    let trimmed = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw CodexAppServerRPCError.invalidEndpoint("Endpoint is empty.")
    }

    let endpointWithScheme = trimmed.contains("://") ? trimmed : "ws://\(trimmed)"
    guard var components = URLComponents(string: endpointWithScheme) else {
      throw CodexAppServerRPCError.invalidEndpoint(endpointText)
    }

    if components.scheme == "http" {
      components.scheme = "ws"
    } else if components.scheme == "https" {
      components.scheme = "wss"
    }

    guard
      let scheme = components.scheme,
      ["ws", "wss"].contains(scheme),
      let url = components.url
    else {
      throw CodexAppServerRPCError.invalidEndpoint(endpointText)
    }

    return url
  }

  private func describe(_ error: Error) -> String {
    if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
      return description
    }
    return String(describing: error)
  }

  private func describeJSON(_ value: Any) -> String {
    if JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    {
      return text
    }
    return String(describing: value)
  }
}

private extension CodexAppServerConnectionState {
  var isConnected: Bool {
    if case .connected = self {
      return true
    }
    return false
  }
}

protocol CodexAppServerBundleInspecting {
  func inspect() -> CodexAppServerBundleStatus
}

struct BundleCodexAppServerInspector: CodexAppServerBundleInspecting {
  func inspect() -> CodexAppServerBundleStatus {
    let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("CodexAppServer", isDirectory: true)
    let binaryURL = resourceURL?.appendingPathComponent("bin/codex", isDirectory: false)
    let manifestURL = resourceURL?.appendingPathComponent("manifest.json", isDirectory: false)
    let isBundlePresent = resourceURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    let isBinaryPresent = binaryURL.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false
    let canExecute = isBinaryPresent && CodexAppServerPlatform.canExecuteBundledServer

    return CodexAppServerBundleStatus(
      resourceURL: resourceURL,
      binaryURL: binaryURL,
      manifestURL: manifestURL,
      isBundlePresent: isBundlePresent,
      isBinaryPresent: isBinaryPresent,
      canExecuteBundledServer: canExecute,
      platformMessage: CodexAppServerPlatform.message(
        isBundlePresent: isBundlePresent,
        isBinaryPresent: isBinaryPresent
      )
    )
  }
}

enum CodexAppServerPlatform {
  static var canExecuteBundledServer: Bool {
    #if os(macOS)
    return true
    #else
    return false
    #endif
  }

  static func message(isBundlePresent: Bool, isBinaryPresent: Bool) -> String {
    guard isBundlePresent else {
      return "The app bundle does not contain CodexAppServer. Build with GOOSE_STAGE_CODEX_APP_SERVER=1 to stage the vendored Codex package."
    }
    guard isBinaryPresent else {
      return "CodexAppServer is present, but bin/codex is missing or not executable."
    }
    guard canExecuteBundledServer else {
      return "CodexAppServer is bundled, but this iOS target cannot spawn a sidecar process. Use the WebSocket endpoint below to talk to a Mac-hosted Codex app-server."
    }
    return "CodexAppServer is bundled and this platform can launch it."
  }
}

protocol CodexAppServerLaunching {
  func start(bundleStatus: CodexAppServerBundleStatus) throws -> String
}

enum CodexAppServerLaunchError: Error {
  case missingBinary
  case unsupportedPlatform
}

struct PlatformCodexAppServerLauncher: CodexAppServerLaunching {
  func start(bundleStatus: CodexAppServerBundleStatus) throws -> String {
    guard let binaryURL = bundleStatus.binaryURL else {
      throw CodexAppServerLaunchError.missingBinary
    }

    #if os(macOS)
    let process = Process()
    process.executableURL = binaryURL
    process.arguments = ["app-server", "--listen", "unix://"]
    process.currentDirectoryURL = Bundle.main.resourceURL
    try process.run()
    return "Started Codex app-server from \(binaryURL.lastPathComponent)"
    #else
    throw CodexAppServerLaunchError.unsupportedPlatform
    #endif
  }
}

enum CodexAppServerRPCEvent {
  case notification(method: String, params: [String: Any])
  case rawMessage(String)
  case closed(String)
}

enum CodexAppServerRPCError: Error, LocalizedError {
  case invalidEndpoint(String)
  case notConnected
  case malformedResponse(String)
  case serverError(String)

  var errorDescription: String? {
    switch self {
    case .invalidEndpoint(let endpoint):
      return "Invalid Codex app-server endpoint: \(endpoint)"
    case .notConnected:
      return "Not connected to Codex app-server."
    case .malformedResponse(let message):
      return "Malformed Codex app-server response: \(message)"
    case .serverError(let message):
      return message
    }
  }
}

@MainActor
final class CodexAppServerRPCClient {
  private let onEvent: @MainActor (CodexAppServerRPCEvent) -> Void
  private var task: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var nextRequestID = 1
  private var pendingRequests: [Int: CheckedContinuation<Any, Error>] = [:]

  init(onEvent: @escaping @MainActor (CodexAppServerRPCEvent) -> Void) {
    self.onEvent = onEvent
  }

  func connect(to endpoint: URL) async throws {
    guard task == nil else {
      return
    }

    let webSocketTask = URLSession.shared.webSocketTask(with: endpoint)
    task = webSocketTask
    webSocketTask.resume()
    receiveTask = Task { [weak self] in
      await self?.receiveLoop()
    }

    _ = try await sendRequest(
      method: "initialize",
      params: [
        "clientInfo": [
          "name": "GooseSwift",
          "title": "Goose Codex Coach",
          "version": "0.1.0",
        ],
        "capabilities": [
          "experimentalApi": true,
        ],
      ]
    )
    try await sendNotification(method: "initialized")
  }

  func disconnect() {
    receiveTask?.cancel()
    receiveTask = nil
    task?.cancel(with: .goingAway, reason: nil)
    task = nil
    completePendingRequests(with: CodexAppServerRPCError.notConnected)
  }

  func sendRequest(method: String, params: [String: Any]) async throws -> Any {
    guard task != nil else {
      throw CodexAppServerRPCError.notConnected
    }

    let requestID = nextRequestID
    nextRequestID += 1

    return try await withCheckedThrowingContinuation { continuation in
      pendingRequests[requestID] = continuation

      Task { [weak self] in
        guard let self else {
          return
        }
        do {
          try await self.sendJSON([
            "id": requestID,
            "method": method,
            "params": params,
          ])
        } catch {
          self.failPendingRequest(id: requestID, error: error)
        }
      }
    }
  }

  func sendNotification(method: String, params: [String: Any]? = nil) async throws {
    var payload: [String: Any] = [
      "method": method,
    ]
    if let params {
      payload["params"] = params
    }
    try await sendJSON(payload)
  }

  private func sendJSON(_ object: [String: Any]) async throws {
    guard let task else {
      throw CodexAppServerRPCError.notConnected
    }
    let data = try JSONSerialization.data(withJSONObject: object)
    guard let text = String(data: data, encoding: .utf8) else {
      throw CodexAppServerRPCError.malformedResponse("Unable to encode request.")
    }
    try await task.send(.string(text))
  }

  private func receiveLoop() async {
    while !Task.isCancelled {
      do {
        guard let task else {
          return
        }
        let message = try await task.receive()
        try handle(message: message)
      } catch {
        if !Task.isCancelled {
          completePendingRequests(with: error)
          onEvent(.closed(describe(error)))
        }
        return
      }
    }
  }

  private func handle(message: URLSessionWebSocketTask.Message) throws {
    switch message {
    case .string(let text):
      try handleText(text)
    case .data(let data):
      guard let text = String(data: data, encoding: .utf8) else {
        throw CodexAppServerRPCError.malformedResponse("Received non-UTF8 data.")
      }
      try handleText(text)
    @unknown default:
      throw CodexAppServerRPCError.malformedResponse("Received unknown WebSocket message type.")
    }
  }

  private func handleText(_ text: String) throws {
    guard
      let data = text.data(using: .utf8),
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw CodexAppServerRPCError.malformedResponse(text)
    }

    if let requestID = requestID(from: object["id"]) {
      guard let continuation = pendingRequests.removeValue(forKey: requestID) else {
        onEvent(.rawMessage(text))
        return
      }

      if let error = object["error"] {
        continuation.resume(throwing: CodexAppServerRPCError.serverError(describeJSON(error)))
      } else {
        continuation.resume(returning: object["result"] ?? NSNull())
      }
      return
    }

    if let method = object["method"] as? String {
      onEvent(.notification(method: method, params: object["params"] as? [String: Any] ?? [:]))
      return
    }

    onEvent(.rawMessage(text))
  }

  private func requestID(from value: Any?) -> Int? {
    if let intValue = value as? Int {
      return intValue
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let string = value as? String {
      return Int(string)
    }
    return nil
  }

  private func failPendingRequest(id: Int, error: Error) {
    guard let continuation = pendingRequests.removeValue(forKey: id) else {
      return
    }
    continuation.resume(throwing: error)
  }

  private func completePendingRequests(with error: Error) {
    let continuations = Array(pendingRequests.values)
    pendingRequests.removeAll()
    for continuation in continuations {
      continuation.resume(throwing: error)
    }
  }

  private func describe(_ error: Error) -> String {
    if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
      return description
    }
    return String(describing: error)
  }

  private func describeJSON(_ value: Any) -> String {
    if JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    {
      return text
    }
    return String(describing: value)
  }
}
