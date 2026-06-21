import Foundation

@MainActor
final class CoachChatModel: ObservableObject {
  @Published private(set) var isSignedIn = false
  @Published private(set) var loginStatus = "No API key"
  @Published private(set) var modelPreset: CoachModelPreset
  @Published private(set) var messages: [CoachChatMessage] = []
  @Published private(set) var streamState: CoachStreamState = .idle
  @Published private(set) var errorMessage: String?

  private static let modelPresetDefaultsKey = "goose.coach.modelPreset"
  private static let seedPromptText = "What should we look at today?"
  private var apiKey: String?
  private var sendTask: Task<Void, Never>?
  private let client = GeminiCoachClient()

  init() {
    let storedRawValue = UserDefaults.standard.string(forKey: Self.modelPresetDefaultsKey)
    modelPreset = storedRawValue.flatMap(CoachModelPreset.init(rawValue:)) ?? .defaultValue
    messages = Self.normalizedPersistedMessages(CoachConversationStore.load())
    if !messages.isEmpty {
      persistConversation()
    }
  }

  deinit {
    sendTask?.cancel()
  }

  func refreshAuth() {
    if let key = CoachAPIKeyStore.load() {
      apiKey = key
      isSignedIn = true
      loginStatus = "API key saved"
      seedAssistantPromptIfNeeded()
    } else {
      apiKey = nil
      isSignedIn = false
      loginStatus = "No API key"
    }
  }

  /// Persist a Gemini API key and unlock the coach. Replaces the OAuth sign-in.
  func saveAPIKey(_ key: String) {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      errorMessage = "Paste a Gemini API key."
      return
    }
    CoachAPIKeyStore.save(trimmed)
    apiKey = trimmed
    isSignedIn = true
    loginStatus = "API key saved"
    errorMessage = nil
    seedAssistantPromptIfNeeded()
  }

  func selectModelPreset(_ preset: CoachModelPreset) {
    modelPreset = preset
    UserDefaults.standard.set(preset.rawValue, forKey: Self.modelPresetDefaultsKey)
  }

  func startNewConversation() {
    sendTask?.cancel()
    sendTask = nil
    streamState = .idle
    errorMessage = nil
    messages.removeAll()
    CoachConversationStore.clear()
    seedAssistantPromptIfNeeded()
  }

  func signOut() {
    sendTask?.cancel()
    sendTask = nil
    CoachAPIKeyStore.clear()
    apiKey = nil
    isSignedIn = false
    loginStatus = "No API key"
    streamState = .idle
    messages.removeAll()
    CoachConversationStore.clear()
  }

  func cancelStreaming() {
    sendTask?.cancel()
    sendTask = nil
    streamState = .idle
    cancelStreamingMessages()
  }

  func send(
    _ prompt: String,
    healthStore: HealthDataStore,
    appModel: WhoofAppModel
  ) {
    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPrompt.isEmpty, !streamState.isStreaming else {
      return
    }
    guard let apiKey else {
      isSignedIn = false
      errorMessage = GeminiCoachError.missingAPIKey.localizedDescription
      return
    }

    let assistantID = UUID()
    let contextualPrompt = contextualPrompt(for: trimmedPrompt)
    messages.append(CoachChatMessage(role: .user, text: trimmedPrompt))
    messages.append(CoachChatMessage(id: assistantID, role: .assistant, text: "", isStreaming: true))
    streamState = .streaming
    errorMessage = nil
    persistConversation()

    sendTask?.cancel()
    sendTask = Task { [weak self] in
      guard let self else {
        return
      }
      do {
        try await streamResponseLoop(
          prompt: trimmedPrompt,
          contextualPrompt: contextualPrompt,
          apiKey: apiKey,
          assistantID: assistantID,
          healthStore: healthStore,
          appModel: appModel
        )
        finishAssistantMessage(assistantID)
        streamState = .idle
      } catch is CancellationError {
        markAssistantMessageCancelled(assistantID)
        streamState = .idle
      } catch where isCancelledError(error) {
        markAssistantMessageCancelled(assistantID)
        streamState = .idle
      } catch {
        let message = describe(error)
        appendAssistantText("\n\(message)", to: assistantID)
        finishAssistantMessage(assistantID)
        errorMessage = message
        streamState = .failed(message)
      }
    }
  }

  private func streamResponseLoop(
    prompt: String,
    contextualPrompt: String,
    apiKey: String,
    assistantID: UUID,
    healthStore: HealthDataStore,
    appModel: WhoofAppModel
  ) async throws {
    let model = modelPreset.modelID
    var contents: [[String: Any]] = [GeminiCoachRequest.userText(contextualPrompt)]

    // Pass 1: let the model request local tools.
    var calls: [GeminiCoachFunctionCall] = []
    let firstBody = GeminiCoachRequest.body(model: model, contents: contents, includeTools: true)
    try await client.stream(apiKey: apiKey, model: model, body: firstBody) { [weak self] item in
      guard let self else {
        return
      }
      switch item {
      case .text(let text):
        appendAssistantText(text, to: assistantID)
      case .functionCall(let call):
        calls.append(call)
        upsertToolEvent(
          CoachToolEvent(
            id: toolEventID(for: call, index: calls.count - 1),
            name: call.name,
            status: "Running",
            arguments: jsonString(call.arguments),
            resultSummary: nil
          ),
          in: assistantID
        )
      }
    }

    guard !calls.isEmpty else {
      return
    }

    // Echo the model's function-call turn (including each thoughtSignature,
    // which Gemini thinking models require back), then the tool results turn.
    let modelParts = calls.map { call -> [String: Any] in
      var part: [String: Any] = ["functionCall": ["name": call.name, "args": call.arguments]]
      if let signature = call.thoughtSignature {
        part["thoughtSignature"] = signature
      }
      return part
    }
    contents.append(["role": "model", "parts": modelParts])

    var responseParts: [[String: Any]] = []
    for (index, call) in calls.enumerated() {
      let output = execute(call: call, healthStore: healthStore, appModel: appModel)
      updateToolEvent(id: toolEventID(for: call, index: index), in: assistantID) { event in
        event.status = "Returned"
        event.resultSummary = summarizeToolOutput(jsonString(output))
      }
      responseParts.append([
        "functionResponse": [
          "name": call.name,
          "response": output,
        ],
      ])
    }
    // Keep the tool results and the answer instruction in a single user turn so
    // the model answers immediately, rather than seeing a second consecutive
    // user message after the function responses.
    responseParts.append([
      "text": "Use the tool outputs above to answer this original Coach question now. Do not request more tools.\n\nOriginal question:\n\(prompt)",
    ])
    contents.append(["role": "user", "parts": responseParts])

    // Pass 2: final answer, no tools.
    let secondBody = GeminiCoachRequest.body(model: model, contents: contents, includeTools: false)
    try await client.stream(apiKey: apiKey, model: model, body: secondBody) { [weak self] item in
      guard let self else {
        return
      }
      if case .text(let text) = item {
        appendAssistantText(text, to: assistantID)
      }
    }

    if isAssistantTextEmpty(assistantID) {
      throw GeminiCoachError.api("Coach returned tool calls but no final reply.")
    }
  }

  private func execute(
    call: GeminiCoachFunctionCall,
    healthStore: HealthDataStore,
    appModel: WhoofAppModel
  ) -> [String: Any] {
    let payload = CoachLocalToolContext.build(healthStore: healthStore, appModel: appModel)
    let tools = payload["tools"] as? [String: Any] ?? [:]

    switch call.name {
    case "load_stats", "get_activities", "get_capture_sessions", "get_raw_session_data":
      let value = tools[call.name] ?? ["error": "tool_not_available", "tool": call.name]
      return ["result": value]
    case "get_data_gaps":
      return [
        "readiness": healthStore.metricInputReadinessSummary(),
        "input_next_action": healthStore.metricInputReadinessNextActionSummary(),
        "score_next_action": healthStore.packetDerivedScoreNextActionSummary(),
        "packet_inputs": healthStore.packetInputStatus,
        "packet_scores": healthStore.packetScoreStatus,
        "capture": tools["get_capture_sessions"] ?? [:],
      ]
    default:
      return ["error": "unknown_tool", "tool": call.name]
    }
  }

  private func toolEventID(for call: GeminiCoachFunctionCall, index: Int) -> String {
    "\(call.name)-\(index)"
  }

  private func appendAssistantText(_ delta: String, to id: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else {
      return
    }
    messages[index].text += delta
  }

  private func contextualPrompt(for prompt: String) -> String {
    let transcript = recentTranscriptContext(excludingCurrentPrompt: prompt)
    guard !transcript.isEmpty else {
      return prompt
    }
    return """
    Recent Coach conversation context:
    \(transcript)

    Current user message:
    \(prompt)
    """
  }

  private func recentTranscriptContext(excludingCurrentPrompt prompt: String) -> String {
    let turns = messages.compactMap { message -> String? in
      guard !message.isStreaming, !message.isCancelled else {
        return nil
      }
      let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty, text != Self.seedPromptText else {
        return nil
      }
      if message.role == .user, text == prompt {
        return nil
      }
      switch message.role {
      case .user:
        return "User: \(text)"
      case .assistant:
        return "Coach: \(text)"
      }
    }
    return boundedContext(from: turns.suffix(12), maxCharacters: 6_000)
  }

  private func boundedContext<S: Sequence>(from turns: S, maxCharacters: Int) -> String where S.Element == String {
    var selected: [String] = []
    var count = 0
    for turn in Array(turns).reversed() {
      let nextCount = count + turn.count + 2
      guard nextCount <= maxCharacters || selected.isEmpty else {
        break
      }
      selected.append(turn)
      count = nextCount
    }
    return selected.reversed().joined(separator: "\n\n")
  }

  private func isAssistantTextEmpty(_ id: UUID) -> Bool {
    guard let message = messages.first(where: { $0.id == id }) else {
      return true
    }
    return message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func upsertToolEvent(_ event: CoachToolEvent, in messageID: UUID) {
    guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }) else {
      return
    }
    if let eventIndex = messages[messageIndex].toolEvents.firstIndex(where: { $0.id == event.id }) {
      messages[messageIndex].toolEvents[eventIndex] = event
    } else {
      messages[messageIndex].toolEvents.append(event)
    }
  }

  private func updateToolEvent(
    id: String,
    in messageID: UUID,
    update: (inout CoachToolEvent) -> Void
  ) {
    guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }) else {
      return
    }
    guard let eventIndex = messages[messageIndex].toolEvents.firstIndex(where: { $0.id == id }) else {
      return
    }
    update(&messages[messageIndex].toolEvents[eventIndex])
  }

  private func finishAssistantMessage(_ id: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else {
      return
    }
    messages[index].isStreaming = false
    if messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       messages[index].toolEvents.isEmpty,
       !messages[index].isCancelled {
      messages.remove(at: index)
    }
    persistConversation()
  }

  private func markAssistantMessageCancelled(_ id: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else {
      return
    }
    messages[index].isStreaming = false
    messages[index].isCancelled = true
    markUnfinishedToolEventsStopped(in: index)
    persistConversation()
  }

  private func cancelStreamingMessages() {
    for index in messages.indices {
      guard messages[index].isStreaming else {
        continue
      }
      messages[index].isStreaming = false
      if messages[index].role == .assistant {
        messages[index].isCancelled = true
        markUnfinishedToolEventsStopped(in: index)
      }
    }
    persistConversation()
  }

  private func markUnfinishedToolEventsStopped(in messageIndex: Int) {
    for eventIndex in messages[messageIndex].toolEvents.indices {
      if messages[messageIndex].toolEvents[eventIndex].status != "Returned" {
        messages[messageIndex].toolEvents[eventIndex].status = "Stopped"
      }
    }
  }

  private func seedAssistantPromptIfNeeded() {
    guard messages.isEmpty else {
      return
    }
    messages.append(
      CoachChatMessage(
        role: .assistant,
        text: Self.seedPromptText
      )
    )
    persistConversation()
  }

  private func summarizeToolOutput(_ output: String) -> String {
    let compact = output
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "  ", with: " ")
    return String(compact.prefix(180))
  }

  private func jsonString(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
      return "{\"error\":\"json_encoding_failed\"}"
    }
    return string
  }

  private func persistConversation() {
    CoachConversationStore.save(messages)
  }

  private func describe(_ error: Error) -> String {
    if isCancelledError(error) {
      return "Generation stopped."
    }
    if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
      return description
    }
    return String(describing: error)
  }

  private func isCancelledError(_ error: Error) -> Bool {
    if let urlError = error as? URLError {
      return urlError.code == .cancelled
    }
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
  }

  private static func normalizedPersistedMessages(_ storedMessages: [CoachChatMessage]) -> [CoachChatMessage] {
    storedMessages.map { message in
      var normalized = message
      if normalized.isStreaming {
        normalized.isStreaming = false
        normalized.isCancelled = true
      }
      if normalized.isCancelled {
        for index in normalized.toolEvents.indices where normalized.toolEvents[index].status != "Returned" {
          normalized.toolEvents[index].status = "Stopped"
        }
      }
      return normalized
    }
  }
}
