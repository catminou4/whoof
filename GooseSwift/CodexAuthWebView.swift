import SwiftUI
import WebKit

enum CodexAuthWebEvent: Equatable {
  case didStart(URL)
  case didFinish(URL)
  case didFail(String)
  case callback(URL)
  case scriptMessage(String)
}

struct CodexAuthWebView: UIViewRepresentable {
  let url: URL
  let onEvent: (CodexAuthWebEvent) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onEvent: onEvent)
  }

  func makeUIView(context: Context) -> WKWebView {
    let userContentController = WKUserContentController()
    userContentController.add(context.coordinator, name: "codexAuth")
    userContentController.addUserScript(
      WKUserScript(
        source: """
        window.addEventListener('message', function(event) {
          window.webkit.messageHandlers.codexAuth.postMessage({
            type: 'window.message',
            origin: event.origin || '',
            data: String(event.data || '')
          });
        });
        """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: false
      )
    )

    let configuration = WKWebViewConfiguration()
    configuration.userContentController = userContentController
    configuration.websiteDataStore = .default()

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.allowsBackForwardNavigationGestures = true
    webView.load(URLRequest(url: url))
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    guard webView.url != url else {
      return
    }
    webView.load(URLRequest(url: url))
  }

  static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
    uiView.navigationDelegate = nil
    uiView.configuration.userContentController.removeScriptMessageHandler(forName: "codexAuth")
  }

  final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let onEvent: (CodexAuthWebEvent) -> Void

    init(onEvent: @escaping (CodexAuthWebEvent) -> Void) {
      self.onEvent = onEvent
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      onEvent(.scriptMessage(describeScriptMessage(message.body)))
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      if let url = navigationAction.request.url, isAppCallback(url) {
        onEvent(.callback(url))
        decisionHandler(.cancel)
        return
      }

      decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
      if let url = webView.url {
        onEvent(.didStart(url))
      }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
      if let url = webView.url {
        onEvent(.didFinish(url))
      }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
      onEvent(.didFail(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
      onEvent(.didFail(error.localizedDescription))
    }

    private func isAppCallback(_ url: URL) -> Bool {
      guard let scheme = url.scheme?.lowercased() else {
        return false
      }
      return ["gooseswift", "goose"].contains(scheme) && url.host == "codex-auth"
    }

    private func describeScriptMessage(_ body: Any) -> String {
      if JSONSerialization.isValidJSONObject(body),
        let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
        let text = String(data: data, encoding: .utf8)
      {
        return text
      }
      return String(describing: body)
    }
  }
}
