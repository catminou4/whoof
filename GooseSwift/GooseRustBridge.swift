import Foundation

enum GooseRustBridgeError: Error {
  case encodingFailed
  case nullResponse
  case malformedResponse
  case methodFailed(String)
}

final class GooseRustBridge {
  private var counter = 0

  func request(method: String, args: [String: Any] = [:]) throws -> [String: Any] {
    try requestValue(method: method, args: args) as? [String: Any] ?? [:]
  }

  func requestValue(method: String, args: [String: Any] = [:]) throws -> Any {
    counter += 1
    let payload: [String: Any] = [
      "schema": "goose.bridge.request.v1",
      "request_id": "goose-swift-\(Date().timeIntervalSince1970)-\(counter)",
      "method": method,
      "args": args,
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)
    guard let request = String(data: data, encoding: .utf8) else {
      throw GooseRustBridgeError.encodingFailed
    }

    var responsePointer: UnsafeMutablePointer<CChar>?
    request.withCString { pointer in
      responsePointer = goose_bridge_handle_json(pointer)
    }
    guard let responsePointer else {
      throw GooseRustBridgeError.nullResponse
    }
    defer {
      goose_bridge_free_string(responsePointer)
    }

    let responseText = String(cString: responsePointer)
    let responseData = Data(responseText.utf8)
    guard
      let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
      let ok = response["ok"] as? Bool
    else {
      throw GooseRustBridgeError.malformedResponse
    }
    if !ok {
      let error = response["error"] as? [String: Any]
      let message = error?["message"] as? String ?? "Rust bridge method failed"
      throw GooseRustBridgeError.methodFailed(message)
    }
    return response["result"] ?? [:]
  }
}
