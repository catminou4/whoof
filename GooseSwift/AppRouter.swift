import Foundation

@MainActor
final class AppRouter: ObservableObject {
  @Published var selectedTab: GooseAppTab = .home
  @Published var healthPath: [HealthRoute] = []
  @Published var codexAuthCallbackURL: URL?

  func openHealth(_ route: HealthRoute?) {
    selectedTab = .health
    if let route {
      healthPath = [route]
    } else {
      healthPath = []
    }
  }

  @discardableResult
  func handleDeepLink(_ url: URL) -> Bool {
    if isCodexAuthCallback(url) {
      selectedTab = .coach
      codexAuthCallbackURL = url
      return true
    }

    guard url.scheme == "gooseswift", url.host == "health" else {
      return false
    }
    let routeName = url.pathComponents.dropFirst().first ?? ""
    if routeName.isEmpty {
      openHealth(nil)
      return true
    }
    guard let route = HealthRoute(rawValue: routeName) else {
      return false
    }
    openHealth(route)
    return true
  }

  private func isCodexAuthCallback(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else {
      return false
    }
    return ["gooseswift", "goose"].contains(scheme) && url.host == "codex-auth"
  }
}
