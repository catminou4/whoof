import Foundation

struct GeminiCoachFunctionCall: Equatable {
  let name: String
  let arguments: [String: Any]
  /// Opaque reasoning token returned alongside a thinking-model function call.
  /// It must be echoed back in the model turn or the follow-up request is
  /// rejected with "Function call is missing a thought_signature".
  let thoughtSignature: String?

  static func == (lhs: GeminiCoachFunctionCall, rhs: GeminiCoachFunctionCall) -> Bool {
    lhs.name == rhs.name
      && lhs.thoughtSignature == rhs.thoughtSignature
      && NSDictionary(dictionary: lhs.arguments).isEqual(to: rhs.arguments)
  }
}

enum GeminiCoachStreamItem {
  case text(String)
  case functionCall(GeminiCoachFunctionCall)
}

enum GeminiCoachError: Error, LocalizedError {
  case missingAPIKey
  case invalidURL
  case invalidRequestBody
  case invalidResponse
  case httpStatus(Int, String)
  case api(String)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "Add a Gemini API key first."
    case .invalidURL:
      return "The Coach Gemini URL is invalid."
    case .invalidRequestBody:
      return "The Coach request could not be encoded."
    case .invalidResponse:
      return "Coach returned an invalid streaming response."
    case .httpStatus(let status, let body):
      return body.isEmpty
        ? "Coach request failed with HTTP \(status)."
        : "Coach request failed with HTTP \(status): \(body)"
    case .api(let message):
      return message
    }
  }
}

/// Streams Google Gemini `streamGenerateContent` responses (Server-Sent Events).
/// Replaces the ChatGPT/Codex Responses client; auth is a free-tier API key
/// passed as the `key` query parameter.
struct GeminiCoachClient {
  private static let base = "https://generativelanguage.googleapis.com/v1beta/models"

  func stream(
    apiKey: String,
    model: String,
    body: [String: Any],
    onItem: @MainActor @escaping (GeminiCoachStreamItem) throws -> Void
  ) async throws {
    guard !apiKey.isEmpty else {
      throw GeminiCoachError.missingAPIKey
    }
    guard var components = URLComponents(string: "\(Self.base)/\(model):streamGenerateContent") else {
      throw GeminiCoachError.invalidURL
    }
    components.queryItems = [
      URLQueryItem(name: "alt", value: "sse"),
    ]
    guard let url = components.url else {
      throw GeminiCoachError.invalidURL
    }
    guard JSONSerialization.isValidJSONObject(body) else {
      throw GeminiCoachError.invalidRequestBody
    }
    let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    // Key as a header, not a URL query param, so it does not land in URL logs.
    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
    request.httpBody = bodyData
    request.timeoutInterval = 180

    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw GeminiCoachError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      let body = try await Self.readErrorBody(from: bytes)
      throw GeminiCoachError.httpStatus(httpResponse.statusCode, body)
    }

    for try await line in bytes.lines {
      try Task.checkCancellation()
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed.hasPrefix("data:") else {
        continue
      }
      let json = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
      guard json != "[DONE]",
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        continue
      }
      if let error = object["error"] as? [String: Any] {
        throw GeminiCoachError.api(error["message"] as? String ?? "Gemini stream error.")
      }
      for item in Self.items(from: object) {
        try await onItem(item)
      }
    }
  }

  private static func items(from object: [String: Any]) -> [GeminiCoachStreamItem] {
    guard let candidates = object["candidates"] as? [[String: Any]] else {
      return []
    }
    var items: [GeminiCoachStreamItem] = []
    for candidate in candidates {
      guard let content = candidate["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]] else {
        continue
      }
      for part in parts {
        if let text = part["text"] as? String, !text.isEmpty {
          items.append(.text(text))
        } else if let call = part["functionCall"] as? [String: Any],
                  let name = call["name"] as? String {
          let arguments = call["args"] as? [String: Any] ?? [:]
          let thoughtSignature = part["thoughtSignature"] as? String
          items.append(.functionCall(GeminiCoachFunctionCall(
            name: name, arguments: arguments, thoughtSignature: thoughtSignature
          )))
        }
      }
    }
    return items
  }

  private static func readErrorBody(from bytes: URLSession.AsyncBytes) async throws -> String {
    var lines: [String] = []
    for try await line in bytes.lines {
      lines.append(line)
      if lines.joined().count > 4000 {
        break
      }
    }
    return lines.joined(separator: "\n")
  }
}
