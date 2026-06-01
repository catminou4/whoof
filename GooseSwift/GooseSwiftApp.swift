import SwiftUI

@main
struct GooseSwiftApp: App {
  @StateObject private var model = GooseAppModel()
  @StateObject private var router = AppRouter()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(model)
        .environmentObject(router)
        .onOpenURL { url in
          _ = router.handleDeepLink(url)
        }
    }
  }
}
