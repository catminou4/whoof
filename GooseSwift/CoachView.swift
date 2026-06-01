import SwiftUI

struct CoachView: View {
  @EnvironmentObject private var model: GooseAppModel
  @EnvironmentObject private var router: AppRouter
  @AppStorage("goose.codex.appServerEndpoint") private var endpointText = "ws://127.0.0.1:17655"
  @StateObject private var appServer = CodexAppServerModel()
  @State private var authPresentation: CodexAuthWebPresentation?

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        CoachHeaderCard()

        CodexServerStatusCard(
          state: appServer.runState,
          bundleStatus: appServer.bundleStatus,
          refresh: appServer.refresh,
          start: appServer.start
        )

        CodexAuthCard(
          endpointText: $endpointText,
          connectionState: appServer.connectionState,
          loginStatus: appServer.loginStatus,
          loginID: appServer.loginID,
          authPresentation: appServer.authWebPresentation,
          deviceCode: appServer.deviceCode,
          connect: { appServer.connect(endpointText: endpointText) },
          disconnect: appServer.disconnect,
          startLogin: { appServer.startChatGPTLogin(endpointText: endpointText) },
          openAuth: { authPresentation = appServer.authWebPresentation }
        )

        CodexMessageLogCard(messages: appServer.messages)
        CoachToolPreviewCard()
        CoachLoginBoundaryCard()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Coach")
    .sheet(item: $authPresentation, onDismiss: appServer.dismissAuthWebView) { presentation in
      NavigationStack {
        CodexAuthWebView(url: presentation.url, onEvent: appServer.handleAuthWebEvent)
          .navigationTitle("OpenAI Login")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Done") {
                authPresentation = nil
                appServer.dismissAuthWebView()
              }
            }
          }
      }
    }
    .onAppear {
      model.recordUIAction("page.opened", detail: "Coach")
      appServer.refresh()
    }
    .onChange(of: appServer.authWebPresentation) { _, presentation in
      authPresentation = presentation
    }
    .onChange(of: router.codexAuthCallbackURL) { _, callbackURL in
      guard let callbackURL else {
        return
      }
      appServer.handleOpenURL(callbackURL)
      router.codexAuthCallbackURL = nil
    }
  }
}

private struct CoachHeaderCard: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: "sparkles")
          .font(.title3.weight(.semibold))
          .foregroundStyle(.blue)
          .frame(width: 34, height: 34)
          .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        VStack(alignment: .leading, spacing: 2) {
          Text("Codex Coach")
            .font(.headline)
          Text("Managed login spike")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Spacer()
      }

      Text("App-owned health data, Codex-managed auth, and a narrow tool bridge for local stats and activities.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct CodexServerStatusCard: View {
  let state: CodexAppServerRunState
  let bundleStatus: CodexAppServerBundleStatus
  let refresh: () -> Void
  let start: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        Image(systemName: statusIcon)
          .font(.headline.weight(.semibold))
          .foregroundStyle(statusColor)
          .frame(width: 32, height: 32)
          .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        VStack(alignment: .leading, spacing: 2) {
          Text(bundleStatus.title)
            .font(.headline)
          Text(state.displayTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }

        Spacer()
      }

      Text(state.displayDetail)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      VStack(spacing: 8) {
        CoachStatusRow(title: "Bundle", value: bundleStatus.isBundlePresent ? "Present" : "Missing")
        CoachStatusRow(title: "Native binary", value: bundleStatus.isBinaryPresent ? "Present" : "Missing")
        CoachStatusRow(title: "Executable here", value: bundleStatus.canExecuteBundledServer ? "Yes" : "No")
      }

      HStack(spacing: 10) {
        Button {
          refresh()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
          start()
        } label: {
          Label("Start", systemImage: "play.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!bundleStatus.canExecuteBundledServer)
      }
    }
    .padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var statusIcon: String {
    if bundleStatus.canExecuteBundledServer {
      return "checkmark.circle.fill"
    }
    if bundleStatus.isBundlePresent {
      return "exclamationmark.triangle.fill"
    }
    return "tray"
  }

  private var statusColor: Color {
    if bundleStatus.canExecuteBundledServer {
      return .green
    }
    if bundleStatus.isBundlePresent {
      return .orange
    }
    return .blue
  }
}

private struct CodexAuthCard: View {
  @Binding var endpointText: String

  let connectionState: CodexAppServerConnectionState
  let loginStatus: String
  let loginID: String?
  let authPresentation: CodexAuthWebPresentation?
  let deviceCode: CodexLoginDeviceCode?
  let connect: () -> Void
  let disconnect: () -> Void
  let startLogin: () -> Void
  let openAuth: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("OpenAI auth", systemImage: "person.crop.circle.badge.checkmark")
        .font(.headline)

      VStack(alignment: .leading, spacing: 8) {
        Text("Codex app-server endpoint")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        TextField("ws://127.0.0.1:17655", text: $endpointText)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)
          .font(.footnote.monospaced())
          .padding(10)
          .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      }

      VStack(spacing: 8) {
        CoachStatusRow(title: "Connection", value: connectionState.title)
        CoachStatusRow(title: "Login", value: loginStatus)
        if let loginID {
          CoachStatusRow(title: "Login ID", value: loginID)
        }
      }

      Text(connectionState.detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if let deviceCode {
        VStack(alignment: .leading, spacing: 8) {
          Text(deviceCode.userCode)
            .font(.title3.monospacedDigit().weight(.semibold))
          Link(deviceCode.verificationURL.absoluteString, destination: deviceCode.verificationURL)
            .font(.caption)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      }

      HStack(spacing: 10) {
        Button {
          connect()
        } label: {
          Label("Connect", systemImage: "point.3.connected.trianglepath.dotted")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(connectionState.title == "Connecting")

        Button {
          startLogin()
        } label: {
          Label("Sign in", systemImage: "person.badge.key")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      }

      HStack(spacing: 10) {
        Button {
          openAuth()
        } label: {
          Label("Open WebView", systemImage: "safari")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(authPresentation == nil)

        Button(role: .cancel) {
          disconnect()
        } label: {
          Label("Disconnect", systemImage: "xmark.circle")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct CodexMessageLogCard: View {
  let messages: [CodexAppServerMessage]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("App-server messages", systemImage: "list.bullet.rectangle")
        .font(.headline)

      if messages.isEmpty {
        Text("No messages yet.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        VStack(spacing: 10) {
          ForEach(messages.prefix(8)) { message in
            CodexMessageRow(message: message)
          }
        }
      }
    }
    .padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct CodexMessageRow: View {
  let message: CodexAppServerMessage

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon)
        .font(.caption.weight(.bold))
        .foregroundStyle(color)
        .frame(width: 22, height: 22)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline) {
          Text(message.title)
            .font(.caption.weight(.semibold))
          Spacer(minLength: 8)
          Text(message.timestamp, style: .time)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
        Text(message.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
    }
  }

  private var icon: String {
    switch message.level {
    case .info:
      return "info"
    case .success:
      return "checkmark"
    case .warning:
      return "exclamationmark"
    case .error:
      return "xmark"
    }
  }

  private var color: Color {
    switch message.level {
    case .info:
      return .blue
    case .success:
      return .green
    case .warning:
      return .orange
    case .error:
      return .red
    }
  }
}

private struct CoachStatusRow: View {
  let title: String
  let value: String

  var body: some View {
    HStack {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
  }
}

private struct CoachToolPreviewCard: View {
  private let tools = [
    ("load_stats", "metric readiness and score snapshots"),
    ("get_activities", "sessions, metrics, and intervals"),
    ("get_capture_sessions", "capture coverage and data gaps"),
    ("get_raw_session_data", "debug-only redacted packet evidence"),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Tool bridge", systemImage: "wrench.and.screwdriver")
        .font(.headline)

      ForEach(tools, id: \.0) { tool in
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
          VStack(alignment: .leading, spacing: 2) {
            Text(tool.0)
              .font(.subheadline.weight(.semibold))
            Text(tool.1)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
      }
    }
    .padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct CoachLoginBoundaryCard: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Login boundary", systemImage: "lock.shield")
        .font(.headline)

      Text("The app requests managed ChatGPT login from Codex and does not handle OpenAI tokens directly. Completion comes back through Codex app-server notifications and app callbacks.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

#Preview {
  NavigationStack {
    CoachView()
      .environmentObject(GooseAppModel(startBLE: false))
      .environmentObject(AppRouter())
  }
}
